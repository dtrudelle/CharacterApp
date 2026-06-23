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
        /// Provenance du groupe : sert à répartir les colonnes de la fiche
        /// (classe + sous-classe d'un côté, espèce de l'autre) sans parser `source`.
        enum Origin { case species, characterClass, subclass }
        var origin: Origin
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
    var initiative: Int          // mod DEX + bonus manuel
    var armorClassComputed: Int  // meilleure CA dérivée des armures + bonus manuel
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
    var hitPointsMax: Int        // PV max (moyenne fixe SRD 2024)
    var hitDiceTotal: Int        // = niveau
    var hitDieType: String       // ex. « d8 »
    var hitDiceRemaining: Int
    var wounds: Int              // score de CON + woundBonus de l'espèce
    /// Points de focus (règle maison) : nombre de cases = modificateur de la stat
    /// de casting. nil si la classe n'est pas wizard/sorcerer/warlock ou si le
    /// modificateur est ≤ 0 (dans ce cas le bloc n'est pas affiché).
    var focusPoints: Int?

    // Descriptif
    var featureGroups: [FeatureGroup]
    var feats: [Feat]
    var knownSpells: [KnownSpellGroup]
    /// Noms d'outils choisis, triés (artisan + kits, liste unique).
    var knownTools: [String]
    /// Équipement possédé, résolu depuis les catalogues et groupé par catégorie.
    var ownedEquipment: [EquipmentGroup]

    struct KnownSpellGroup: Identifiable {
        var level: Int
        var names: [String]
        var id: Int { level }
        var title: String { level == 0 ? "Cantrips" : "Level \(level)" }
    }

    /// Un groupe d'équipement possédé pour l'affichage (catégorie + noms triés).
    struct EquipmentGroup: Identifiable {
        var category: String   // « Armes », « Armures », « Outils », « Équipement »
        var names: [String]
        var id: String { category }
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
        var tools: [String: Tool] = [:]     // id → outil, pour résoudre chosenToolIds & ownedToolIds
        var weapons: [String: EquipmentItem] = [:]  // id → arme, pour ownedWeaponIds
        var armor: [String: EquipmentItem] = [:]    // id → armure, pour ownedArmorIds
        var gear: [String: EquipmentItem] = [:]     // id → équipement, pour ownedGearIds
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

        // Points de focus (règle maison) : uniquement wizard, sorcerer, warlock ;
        // nombre = modificateur de la stat de casting (nil si ≤ 0).
        var focus: Int? = nil
        let isFocusClass = ["wizard", "sorcerer", "warlock"].contains {
            cls.name.lowercased() == $0 || cls.id.lowercased().hasSuffix("_\($0)")
        }
        if isFocusClass, let sa = cls.spellcastingAbility {
            let mod = abilities.modifier(sa)
            if mod > 0 { focus = mod }
        }

        return ComputedSheet(
            finalAbilities: abilities,
            proficiencyBonus: pb,
            saves: saves,
            skills: skills,
            initiative: abilities.modifier(.DEX) + ch.initiativeBonus,
            armorClassComputed: armorClass(ch, refs, dexMod: abilities.modifier(.DEX)) + ch.armorClassBonus,
            toHitSTR: abilities.modifier(.STR) + pb,
            toHitDEX: abilities.modifier(.DEX) + pb,
            damageSTR: abilities.modifier(.STR),
            damageDEX: abilities.modifier(.DEX),
            spellSaveDC: dc,
            spellAttackBonus: atk,
            spellSlots: spellSlots(casterType: cls.casterType, level: ch.level),
            cantripsKnown: cantrips,
            preparedSpells: prepared,
            hitPointsMax: maxHitPoints(hitDie: cls.hitDie, level: ch.level, conMod: abilities.modifier(.CON)) + ch.hitPointsBonus,
            hitDiceTotal: ch.level,
            hitDieType: cls.hitDie,
            hitDiceRemaining: max(0, ch.level - ch.hitDiceUsed),
            wounds: abilities.score(.CON) + refs.species.woundBonus,
            focusPoints: focus,
            featureGroups: featureGroups(ch, refs),
            feats: feats(ch, refs),
            knownSpells: knownSpells(ch, refs),
            knownTools: knownTools(ch, refs),
            ownedEquipment: ownedEquipment(ch, refs)
        )
    }

    // MARK: Formules

    /// Bonus de maîtrise : 2 + ⌊(niveau − 1) / 4⌋.
    static func proficiencyBonus(level: Int) -> Int {
        2 + (max(1, level) - 1) / 4
    }

    /// Scores finaux = base + somme des allocations de toutes les `abilityIncreases`
    /// + les +1 accordés par les dons choisis (`FeatChoice.abilityBonus`).
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
        for fc in ch.featChoices {
            guard let a = fc.abilityBonus else { continue }
            switch a {
            case .STR: s.STR += 1
            case .DEX: s.DEX += 1
            case .CON: s.CON += 1
            case .INT: s.INT += 1
            case .WIS: s.WIS += 1
            case .CHA: s.CHA += 1
            }
        }
        return s
    }

    // MARK: Points de vie

    /// Taille du dé de vie à partir de « d8 » → 8 (défaut 8 si non parsable).
    static func hitDieSize(_ hitDie: String) -> Int {
        Int(hitDie.filter { $0.isNumber }) ?? 8
    }

    /// PV max « optimaux » : dé max + mod CON à **chaque** niveau (plancher 1 PV
    /// par niveau). Ex. Clerc d8 niveau 2, CON +1 → 2 × (8 + 1) = 18.
    static func maxHitPoints(hitDie: String, level: Int, conMod: Int) -> Int {
        let lvl = max(1, level)
        let die = hitDieSize(hitDie)
        return lvl * max(1, die + conMod)
    }

    // MARK: Classe d'armure

    /// Composantes d'une armure de corps, dérivées du champ `detail`.
    /// `dexCap == nil` → aucune DEX (lourde) ; `Int.max` → DEX non plafonnée
    /// (légère) ; valeur finie → plafond (intermédiaire).
    private struct ArmorAC { var base: Int; var dexCap: Int? }

    /// Parse « AC 14 + Dex modifier (max 2) » → base 14, plafond DEX 2.
    /// Renvoie nil si aucune base « AC N » (ex. le bouclier « +2 AC »).
    private static func parseArmorAC(_ detail: String) -> ArmorAC? {
        guard let r = detail.range(of: #"AC\s+\d+"#, options: .regularExpression),
              let base = Int(detail[r].filter(\.isNumber)) else { return nil }
        let hasDex = detail.range(of: "Dex modifier", options: .caseInsensitive) != nil
        guard hasDex else { return ArmorAC(base: base, dexCap: nil) }
        if let capR = detail.range(of: #"\(max\s+\d+\)"#, options: .regularExpression) {
            return ArmorAC(base: base, dexCap: Int(detail[capR].filter(\.isNumber)) ?? .max)
        }
        return ArmorAC(base: base, dexCap: .max)
    }

    /// Bonus du bouclier (« +2 AC » → 2 ; défaut 2).
    private static func parseShieldBonus(_ detail: String) -> Int {
        guard let r = detail.range(of: #"\+\d+"#, options: .regularExpression) else { return 2 }
        return Int(detail[r].filter(\.isNumber)) ?? 2
    }

    /// Meilleure CA : base de la plus grosse armure portée + DEX (plafonnée selon
    /// le type) + bouclier. Sans armure : 10 + DEX. Le groupe « Shield » distingue
    /// le bouclier des armures de corps.
    static func armorClass(_ ch: Character, _ refs: References, dexMod: Int) -> Int {
        var bodyACs: [Int] = []
        var shieldBonus = 0
        for id in ch.ownedArmorIds {
            guard let item = refs.armor[id] else { continue }
            if item.group == "Shield" {
                shieldBonus = max(shieldBonus, parseShieldBonus(item.detail))
                continue
            }
            guard let ac = parseArmorAC(item.detail) else { continue }
            let dexPart: Int
            switch ac.dexCap {
            case .none:           dexPart = 0
            case .some(let cap):  dexPart = min(dexMod, cap)
            }
            bodyACs.append(ac.base + dexPart)
        }
        let best = bodyACs.max() ?? (10 + dexMod)   // non armuré
        return best + shieldBonus
    }

    /// Valeurs de combat AUTO (sans bonus manuel), pour l'éditeur qui affiche le
    /// détail « base + bonus ». La fiche, elle, additionne directement les offsets.
    struct CombatBases {
        var hitPoints: Int
        var armorClass: Int
        var initiative: Int
    }

    static func combatBases(_ ch: Character, _ refs: References) -> CombatBases {
        let ab = finalAbilities(ch)
        return CombatBases(
            hitPoints: maxHitPoints(hitDie: refs.characterClass.hitDie, level: ch.level, conMod: ab.modifier(.CON)),
            armorClass: armorClass(ch, refs, dexMod: ab.modifier(.DEX)),
            initiative: ab.modifier(.DEX)
        )
    }

    static func featureGroups(_ ch: Character, _ refs: References) -> [ComputedSheet.FeatureGroup] {
        var groups: [ComputedSheet.FeatureGroup] = []

        if !refs.species.traits.isEmpty {
            groups.append(.init(origin: .species,
                                source: "Espèce — \(refs.species.name)",
                                features: refs.species.traits))
        }

        let classFeatures = refs.characterClass.features.filter { ($0.level ?? 1) <= ch.level }
        if !classFeatures.isEmpty {
            groups.append(.init(origin: .characterClass,
                                source: "Classe — \(refs.characterClass.name)",
                                features: classFeatures))
        }

        if let sub = refs.subclass {
            let subFeatures = sub.features.filter { ($0.level ?? 1) <= ch.level }
            if !subFeatures.isEmpty {
                groups.append(.init(origin: .subclass,
                                    source: "Sous-classe — \(sub.name)",
                                    features: subFeatures))
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

    /// Équipement possédé, résolu en noms triés et groupé par catégorie (ordre
    /// fixe). Les outils possédés réutilisent le catalogue d'outils (`refs.tools`).
    /// Les groupes vides sont omis.
    static func ownedEquipment(_ ch: Character, _ refs: References) -> [ComputedSheet.EquipmentGroup] {
        func names(_ ids: [String], _ dict: [String: EquipmentItem]) -> [String] {
            ids.compactMap { dict[$0]?.name }.sorted()
        }
        let toolNames = ch.ownedToolIds.compactMap { refs.tools[$0]?.name }.sorted()
        let groups: [(String, [String])] = [
            ("Armes", names(ch.ownedWeaponIds, refs.weapons)),
            ("Armures", names(ch.ownedArmorIds, refs.armor)),
            ("Outils", toolNames),
            ("Équipement", names(ch.ownedGearIds, refs.gear))
        ]
        return groups.compactMap { category, ns in
            ns.isEmpty ? nil : ComputedSheet.EquipmentGroup(category: category, names: ns)
        }
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
//          · emplacements [1:4, 2:3, 3:2] · dés de vie 5d8 (restants 3) · wounds 24
//          · PV max 50 (5 × (8 + 2)).

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
            hitDiceUsed: 2,
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
