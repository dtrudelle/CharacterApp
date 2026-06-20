import Foundation

// =====================================================================
//  SheetBuilder.swift
//  Moteur de dérivation : (Character + entrées de bibliothèque) → ComputedSheet.
//  Pur et déterministe (aucune dépendance UI, aucun aléatoire).
// =====================================================================

// MARK: - Sortie : la fiche calculée

struct ComputedSheet {

    struct SkillLine {
        var skill: Skill
        var total: Int
        var proficient: Bool
        var expertise: Bool
    }

    struct SlotLine {
        var spellLevel: Int   // niveau de sort (1…9)
        var count: Int        // nombre d'emplacements
    }

    struct FeatureGroup {
        var source: String    // ex. « Classe — Clerc »
        var features: [Trait]
    }

    // Caractéristiques
    var finalAbilities: AbilityScores
    var proficiencyBonus: Int

    // Sauvegardes & compétences
    var saves: [Ability: Int]
    var skills: [SkillLine]

    // Combat
    var initiativeText: String   // repris tel quel (saisi manuellement)
    var toHitSTR: Int
    var toHitDEX: Int
    var damageSTR: Int
    var damageDEX: Int

    // Sorts
    var spellSaveDC: Int?        // nil si non-lanceur
    var spellAttackBonus: Int?
    var spellSlots: [SlotLine]
    var cantripsKnown: Int?      // nombre de tours de magie connus au niveau actuel
    var preparedSpells: Int?     // nombre de sorts préparés au niveau actuel

    // Santé
    var hitDiceTotal: Int        // = niveau
    var hitDieType: String       // ex. « d8 »
    var hitDiceRemaining: Int
    var wounds: Int              // 10 + score de CON

    // Descriptif
    var featureGroups: [FeatureGroup]
    var feats: [Feat]
    var knownSpells: [KnownSpellGroup]
    /// Noms d'outils choisis, triés (artisan + kits, liste unique).
    var knownTools: [String]

    struct KnownSpellGroup: Identifiable {
        var level: Int
        var names: [String]
        var id: Int { level }
        var title: String { level == 0 ? "Cantrips" : "Level \(level)" }
    }

    /// Représentation « 5d8 » du pool de dés de vie.
    var hitDiceLabel: String { "\(hitDiceTotal)\(hitDieType)" }
}

// MARK: - Moteur

struct SheetBuilder {

    /// Entrées de bibliothèque déjà résolues pour ce personnage.
    /// (La résolution id → objet est faite en amont par la couche bibliothèque.)
    struct References {
        var species: Species
        var background: Background
        var characterClass: CharacterClass
        var subclass: Subclass?
        var feats: [String: Feat]   // id → don, pour résoudre originFeatId & featChoices
        var spells: [String: Spell] = [:]   // id → sort, pour résoudre knownSpellIds
        var tools: [String: Tool] = [:]     // id → outil, pour résoudre chosenToolIds
    }

    // MARK: Point d'entrée

    static func build(_ ch: Character, _ refs: References) -> ComputedSheet {
        let abilities = finalAbilities(ch)
        let pb = proficiencyBonus(level: ch.level)
        let cls = refs.characterClass

        // Sauvegardes
        var saves: [Ability: Int] = [:]
        for a in Ability.allCases {
            saves[a] = abilities.modifier(a) + (cls.saveProficiencies.contains(a) ? pb : 0)
        }

        // Compétences
        let proficient = Set(refs.background.skillProficiencies + ch.chosenClassSkills)
        let expert = Set(ch.expertise)
        let skills: [ComputedSheet.SkillLine] = Skill.allCasesSorted.map { sk in
            let mod = abilities.modifier(sk.ability)
            let isExpert = expert.contains(sk)
            let isProf = proficient.contains(sk) || isExpert
            let bonus = isExpert ? 2 * pb : (isProf ? pb : 0)
            return .init(skill: sk, total: mod + bonus, proficient: isProf, expertise: isExpert)
        }

        // Sorts
        var dc: Int?
        var atk: Int?
        if let sa = cls.spellcastingAbility {
            dc = 8 + pb + abilities.modifier(sa)
            atk = pb + abilities.modifier(sa)
        }
        let lvlIdx = min(20, max(1, ch.level)) - 1
        let cantrips = cls.cantripsKnownByLevel.indices.contains(lvlIdx) ? cls.cantripsKnownByLevel[lvlIdx] : nil
        let prepared = cls.preparedSpellsByLevel.indices.contains(lvlIdx) ? cls.preparedSpellsByLevel[lvlIdx] : nil

        return ComputedSheet(
            finalAbilities: abilities,
            proficiencyBonus: pb,
            saves: saves,
            skills: skills,
            initiativeText: ch.initiativeText,
            toHitSTR: abilities.modifier(.STR) + pb,
            toHitDEX: abilities.modifier(.DEX) + pb,
            damageSTR: abilities.modifier(.STR),
            damageDEX: abilities.modifier(.DEX),
            spellSaveDC: dc,
            spellAttackBonus: atk,
            spellSlots: spellSlots(casterType: cls.casterType, level: ch.level),
            cantripsKnown: cantrips,
            preparedSpells: prepared,
            hitDiceTotal: ch.level,
            hitDieType: cls.hitDie,
            hitDiceRemaining: max(0, ch.level - ch.hitDiceUsed),
            wounds: 10 + abilities.score(.CON),
            featureGroups: featureGroups(ch, refs),
            feats: feats(ch, refs),
            knownSpells: knownSpells(ch, refs),
            knownTools: knownTools(ch, refs)
        )
    }

    // MARK: Formules

    /// Bonus de maîtrise : 2 + ⌊(niveau − 1) / 4⌋.
    static func proficiencyBonus(level: Int) -> Int {
        2 + (max(1, level) - 1) / 4
    }

    /// Scores finaux = base + somme des allocations de toutes les `abilityIncreases`.
    static func finalAbilities(_ ch: Character) -> AbilityScores {
        var s = ch.baseAbilities
        for inc in ch.abilityIncreases {
            for (a, v) in inc.allocations {
                switch a {
                case .STR: s.STR += v
                case .DEX: s.DEX += v
                case .CON: s.CON += v
                case .INT: s.INT += v
                case .WIS: s.WIS += v
                case .CHA: s.CHA += v
                }
            }
        }
        return s
    }

    // MARK: Capacités & dons assemblés

    static func featureGroups(_ ch: Character, _ refs: References) -> [ComputedSheet.FeatureGroup] {
        var groups: [ComputedSheet.FeatureGroup] = []

        if !refs.species.traits.isEmpty {
            groups.append(.init(source: "Espèce — \(refs.species.name)", features: refs.species.traits))
        }

        let classFeatures = refs.characterClass.features.filter { ($0.level ?? 1) <= ch.level }
        if !classFeatures.isEmpty {
            groups.append(.init(source: "Classe — \(refs.characterClass.name)", features: classFeatures))
        }

        if let sub = refs.subclass {
            let subFeatures = sub.features.filter { ($0.level ?? 1) <= ch.level }
            if !subFeatures.isEmpty {
                groups.append(.init(source: "Sous-classe — \(sub.name)", features: subFeatures))
            }
        }
        return groups
    }

    /// Dons affichés : don d'origine de l'historique d'abord, puis les dons pris
    /// en niveau (dédupliqués, dans l'ordre).
    static func feats(_ ch: Character, _ refs: References) -> [Feat] {
        var ids: [String] = []
        if let origin = refs.background.originFeatId { ids.append(origin) }
        for choice in ch.featChoices { ids.append(choice.featId) }

        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let feat = refs.feats[id] else { return nil }
            return feat
        }
    }

    /// Sorts cochés, résolus puis groupés par niveau (noms triés).
    static func knownSpells(_ ch: Character, _ refs: References) -> [ComputedSheet.KnownSpellGroup] {
        let resolved = ch.knownSpellIds.compactMap { refs.spells[$0] }
        let byLevel = Dictionary(grouping: resolved, by: \.level)
        return byLevel.keys.sorted().map { lvl in
            ComputedSheet.KnownSpellGroup(level: lvl, names: byLevel[lvl]!.map(\.name).sorted())
        }
    }

    /// Outils choisis, résolus en noms triés (liste unique artisan + kits).
    static func knownTools(_ ch: Character, _ refs: References) -> [String] {
        ch.chosenToolIds.compactMap { refs.tools[$0]?.name }.sorted()
    }

    // MARK: Emplacements de sorts

    static func spellSlots(casterType: CasterType, level: Int) -> [ComputedSheet.SlotLine] {
        let lvl = min(20, max(1, level))

        func lines(_ table: [[Int]]) -> [ComputedSheet.SlotLine] {
            table[lvl - 1].enumerated().compactMap { i, count in
                count > 0 ? .init(spellLevel: i + 1, count: count) : nil
            }
        }

        switch casterType {
        case .none:
            return []
        case .full:
            return lines(SlotTables.full)
        case .half:
            return lines(SlotTables.half)
        case .third:
            return lines(SlotTables.third)
        case .pact:
            guard let p = SlotTables.pact(level: lvl) else { return [] }
            return [.init(spellLevel: p.slotLevel, count: p.count)]
        }
    }
}

// MARK: - Tables d'emplacements (transcrites du SRD 5.2)
// Chaque ligne (indexée par niveau − 1) liste le nombre d'emplacements par
// niveau de sort, du 1er au 9e. Une ligne vide = aucun emplacement à ce niveau.

private enum SlotTables {

    static let full: [[Int]] = [
        [2],
        [3],
        [4, 2],
        [4, 3],
        [4, 3, 2],
        [4, 3, 3],
        [4, 3, 3, 1],
        [4, 3, 3, 2],
        [4, 3, 3, 3, 1],
        [4, 3, 3, 3, 2],
        [4, 3, 3, 3, 2, 1],
        [4, 3, 3, 3, 2, 1],
        [4, 3, 3, 3, 2, 1, 1],
        [4, 3, 3, 3, 2, 1, 1],
        [4, 3, 3, 3, 2, 1, 1, 1],
        [4, 3, 3, 3, 2, 1, 1, 1],
        [4, 3, 3, 3, 2, 1, 1, 1, 1],
        [4, 3, 3, 3, 3, 1, 1, 1, 1],
        [4, 3, 3, 3, 3, 2, 1, 1, 1],
        [4, 3, 3, 3, 3, 2, 2, 1, 1]
    ]

    static let half: [[Int]] = [
        [],
        [2],
        [3],
        [3],
        [4, 2],
        [4, 2],
        [4, 3],
        [4, 3],
        [4, 3, 2],
        [4, 3, 2],
        [4, 3, 3],
        [4, 3, 3],
        [4, 3, 3, 1],
        [4, 3, 3, 1],
        [4, 3, 3, 2],
        [4, 3, 3, 2],
        [4, 3, 3, 3, 1],
        [4, 3, 3, 3, 1],
        [4, 3, 3, 3, 2],
        [4, 3, 3, 3, 2]
    ]

    static let third: [[Int]] = [
        [],
        [],
        [2],
        [3],
        [3],
        [3],
        [4, 2],
        [4, 2],
        [4, 2],
        [4, 3],
        [4, 3],
        [4, 3],
        [4, 3, 2],
        [4, 3, 2],
        [4, 3, 2],
        [4, 3, 3],
        [4, 3, 3],
        [4, 3, 3],
        [4, 3, 3, 1],
        [4, 3, 3, 1]
    ]

    /// Magie de pacte : un nombre d'emplacements, tous du même niveau.
    static func pact(level: Int) -> (count: Int, slotLevel: Int)? {
        guard level >= 1 else { return nil }
        let count: Int
        switch level {
        case 1:        count = 1
        case 2...10:   count = 2
        case 11...16:  count = 3
        default:       count = 4   // 17+
        }
        let slotLevel: Int
        switch level {
        case 1...2:    slotLevel = 1
        case 3...4:    slotLevel = 2
        case 5...6:    slotLevel = 3
        case 7...8:    slotLevel = 4
        default:       slotLevel = 5   // 9+
        }
        return (count, slotLevel)
    }
}

// MARK: - Exemple de vérification (hors UI)
// Permet de contrôler le moteur sans interface : construire l'exemple, appeler
// `SheetBuilder.build`, comparer aux valeurs attendues ci-dessous.
//
// Aurelia Vance — Clerc 5, Domaine de la Vie, Humaine, historique Sage.
// Scores finaux : STR 13, DEX 10, CON 14, INT 11, WIS 16, CHA 12.
// Attendu : maîtrise +3 · save WIS +6 · save CHA +4 · Medicine +6 · Religion +3
//          · toucher STR +4 · DC de sort 14 · attaque de sort +6
//          · emplacements [1:4, 2:3, 3:2] · dés de vie 5d8 (restants 3) · wounds 24.

extension SheetBuilder {

    static var exampleCharacter: Character {
        Character(
            name: "Aurelia Vance",
            playerName: "David",
            speciesId: "humain",
            backgroundId: "sage",
            classId: "clerc",
            subclassId: "domaine-de-la-vie",
            level: 5,
            baseAbilities: AbilityScores(STR: 13, DEX: 10, CON: 13, INT: 11, WIS: 12, CHA: 12),
            abilityIncreases: [
                AbilityIncrease(source: "Background (Sage)", allocations: [.WIS: 2, .CON: 1]),
                AbilityIncrease(source: "Level 4", allocations: [.WIS: 2])
            ],
            chosenClassSkills: [.medecine, .religion],
            armorClassText: "18 (cotte de mailles + bouclier)",
            hitPointsText: "38 / 38",
            initiativeText: "+0",
            hitDiceUsed: 2,
            spellListText: """
            Tours : Flamme sacrée, Lumière, Réparation
            Niv. 1 : Soin des blessures, Bénédiction, Mot de guérison, Sanctuaire
            Niv. 2 : Arme spirituelle, Restauration mineure
            Niv. 3 : Esprits gardiens, Dissipation de la magie
            """,
            equipmentText: "Masse d'armes, cotte de mailles, bouclier, symbole sacré, sac d'exploration",
            currency: Currency(aureon: 15, solari: 8, scaille: 40),
            notesText: "Promise au temple de Lathandre."
        )
    }

    static var exampleReferences: References {
        References(
            species: Species(id: "humain", name: "Humaine", traits: [
                Trait(name: "Polyvalente", description: "Feat d'origine au choix."),
                Trait(name: "Skill", description: "Maîtrise d'un skill supplémentaire.")
            ]),
            background: Background(
                id: "sage", name: "Sage",
                abilityOptions: [.CON, .INT, .WIS],
                skillProficiencies: [.arcanes, .histoire],
                originFeatId: "initie-magie",
                toolProficiency: "Matériel de calligraphe",
                equipmentText: "Bâton, livre, …"
            ),
            characterClass: CharacterClass(
                id: "clerc", name: "Clerc",
                hitDie: "d8",
                saveProficiencies: [.WIS, .CHA],
                casterType: .full,
                spellcastingAbility: .WIS,
                skillChoiceCount: 2,
                skillChoiceOptions: [.histoire, .intuition, .medecine, .persuasion, .religion],
                asiLevels: [4, 8, 12, 16, 19],
                features: [
                    Trait(name: "Incantation", description: "…", level: 1),
                    Trait(name: "Ordre divin", description: "…", level: 1),
                    Trait(name: "Canaliser la divinité", description: "…", level: 2)
                ]
            ),
            subclass: Subclass(
                id: "domaine-de-la-vie", name: "Domaine de la Vie",
                parentClassId: "clerc",
                features: [Trait(name: "Disciple de la vie", description: "…", level: 3)]
            ),
            feats: [
                "initie-magie": Feat(id: "initie-magie", name: "Initié à la magie (clerc)",
                                     category: .origin,
                                     shortEffect: "Deux tours de magie et un sort de niveau 1 par repos long.")
            ]
        )
    }
}
