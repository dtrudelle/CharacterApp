import Foundation
import Observation

// =====================================================================
//  ContentLibrary.swift
//  Bibliothèque de contenu (espèces, historiques, classes, sous-classes, dons).
//
//  Deux couches fusionnées dans les mêmes tableaux :
//   • SRD 2024 embarqué (lecture seule, jamais modifié) ;
//   • entrées « maison » (isCustom == true), éditables et persistées à part
//     dans Application Support/CharacterApp/custom-content.json.
//
//  Les call sites (CharacterEditorView, CharacterApp, SheetBuilder) ne lisent
//  que `species/backgrounds/classes/subclasses/feats` et `references(for:)` :
//  ces cinq propriétés et cette méthode restent inchangées.
// =====================================================================

@Observable
final class ContentLibrary {
    private(set) var species: [Species] = []
    private(set) var backgrounds: [Background] = []
    private(set) var classes: [CharacterClass] = []
    private(set) var subclasses: [Subclass] = []
    private(set) var feats: [Feat] = []
    /// Sorts du SRD (lecture seule, noms + niveau + classes ; pas de version maison).
    private(set) var spells: [Spell] = []
    /// Outils du SRD (lecture seule, artisan + kits ; pas de version maison).
    private(set) var tools: [Tool] = []
    /// Catalogues d'équipement du SRD (lecture seule, comme `tools`).
    private(set) var weapons: [EquipmentItem] = []
    private(set) var armor: [EquipmentItem] = []
    private(set) var gear: [EquipmentItem] = []

    /// Injectable pour les tests ; sinon Application Support/CharacterApp/custom-content.json.
    private let customURL: URL?

    init(customURL: URL? = nil) {
        self.customURL = customURL ?? ContentLibrary.defaultCustomURL
    }

    // MARK: - Résolution des références (inchangé)

    /// Résout les références d'un personnage (id → objets) pour `SheetBuilder`.
    func references(for ch: Character) -> SheetBuilder.References? {
        guard let sp = species.first(where: { $0.id == ch.speciesId }),
              let bg = backgrounds.first(where: { $0.id == ch.backgroundId }),
              let cl = classes.first(where: { $0.id == ch.classId }) else { return nil }
        let sub = ch.subclassId.flatMap { id in subclasses.first(where: { $0.id == id }) }
        let featDict = Dictionary(feats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let spellDict = Dictionary(spells.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let toolDict = Dictionary(tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let weaponDict = Dictionary(weapons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let armorDict = Dictionary(armor.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let gearDict = Dictionary(gear.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return SheetBuilder.References(species: sp, background: bg,
                                       characterClass: cl, subclass: sub,
                                       feats: featDict, spells: spellDict, tools: toolDict,
                                       weapons: weaponDict, armor: armorDict, gear: gearDict)
    }

    // MARK: - Chargement

    /// Fabrique standard de l'app : SRD embarqué (ou amorçage si absent) + maison.
    static func loadBundled(customURL: URL? = nil) -> ContentLibrary {
        let lib = ContentLibrary(customURL: customURL)
        lib.loadBundledSRD()
        lib.loadCustom()
        lib.sortAll()
        return lib
    }

    /// Fabrique en mémoire pour les aperçus SwiftUI : peuplée depuis l'amorçage,
    /// sans aucune lecture du bundle ni du disque (persistance désactivée).
    static var preview: ContentLibrary {
        let lib = ContentLibrary(customURL: nil)
        let s = seed
        lib.species = s.species; lib.backgrounds = s.backgrounds; lib.classes = s.classes
        lib.subclasses = s.subclasses; lib.feats = s.feats
        lib.sortAll()
        return lib
    }

    /// Charge les cinq JSON SRD du bundle, fichier par fichier. Chaque fichier
    /// absent ou invalide est signalé en console par son nom (au lieu d'un échec
    /// silencieux tout-ou-rien). On ne retombe sur l'amorçage `.seed` que pour
    /// les types réellement introuvables, et seulement pour éviter une lib vide
    /// (qui ferait planter l'éditeur sur `classes[0]`).
    private func loadBundledSRD() {
        species     = Self.loadResource("srd-2024-species")     ?? []
        backgrounds = Self.loadResource("srd-2024-backgrounds") ?? []
        classes     = Self.loadResource("srd-2024-classes")     ?? []
        subclasses  = Self.loadResource("srd-2024-subclasses")  ?? []
        feats       = Self.loadResource("srd-2024-feats")       ?? []
        spells      = Self.loadResource("srd-2024-spells")      ?? []
        tools       = Self.loadResource("srd-2024-tools")       ?? []
        weapons     = Self.loadResource("srd-2024-weapons")     ?? []
        armor       = Self.loadResource("srd-2024-armor")       ?? []
        gear        = Self.loadResource("srd-2024-gear")        ?? []

        // Filet de sécurité : si AUCUN fichier SRD n'a été trouvé (ressources non
        // ajoutées à la cible), on amorce avec le jeu de test pour rester utilisable.
        if species.isEmpty && backgrounds.isEmpty && classes.isEmpty
            && subclasses.isEmpty && feats.isEmpty {
            print("⚠️ Aucun JSON SRD trouvé dans le bundle — repli sur le jeu de test. "
                + "Ajoutez srd-2024-*.json à la cible CharacterApp (Target Membership).")
            let s = Self.seed
            species = s.species; backgrounds = s.backgrounds; classes = s.classes
            subclasses = s.subclasses; feats = s.feats
        }
    }

    private static func loadResource<T: Decodable>(_ name: String) -> [T]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("⚠️ \(name).json introuvable dans le bundle (Target Membership ?).")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ \(name).json présent mais illisible.")
            return nil
        }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("⚠️ \(name).json présent mais invalide : \(error)")
            return nil
        }
    }

    // MARK: - Statut maison

    func isCustom(species id: Species.ID)    -> Bool { species.first { $0.id == id }?.isCustom ?? false }
    func isCustom(background id: Background.ID) -> Bool { backgrounds.first { $0.id == id }?.isCustom ?? false }
    func isCustom(class id: CharacterClass.ID) -> Bool { classes.first { $0.id == id }?.isCustom ?? false }
    func isCustom(subclass id: Subclass.ID)  -> Bool { subclasses.first { $0.id == id }?.isCustom ?? false }
    func isCustom(feat id: Feat.ID)          -> Bool { feats.first { $0.id == id }?.isCustom ?? false }
    func isCustom(spell id: Spell.ID)        -> Bool { spells.first { $0.id == id }?.isCustom ?? false }

    // MARK: - Upsert (insère ou met à jour une entrée maison)

    func upsert(_ s: Species)        { var v = s; v.isCustom = true; upsertInto(&species, v); persist() }
    func upsert(_ b: Background)     { var v = b; v.isCustom = true; upsertInto(&backgrounds, v); persist() }
    func upsert(_ c: CharacterClass) { var v = c; v.isCustom = true; upsertInto(&classes, v); persist() }
    func upsert(_ s: Subclass)       { var v = s; v.isCustom = true; upsertInto(&subclasses, v); persist() }
    func upsert(_ f: Feat)           { var v = f; v.isCustom = true; upsertInto(&feats, v); persist() }
    func upsert(_ s: Spell)          { var v = s; v.isCustom = true; upsertInto(&spells, v); persist() }

    // MARK: - Suppression (refuse de toucher au SRD)

    // La persistance est appelée APRÈS la mutation, jamais pendant : `deleteCustom`
    // détient le tableau en accès exclusif (inout) et `persist()` y re-accède en
    // lecture, ce qui violerait l'exclusivité (crash « Simultaneous accesses »).

    func deleteSpecies(_ id: Species.ID)       { if deleteCustom(from: &species, id: id)     { persist() } }
    func deleteBackground(_ id: Background.ID) { if deleteCustom(from: &backgrounds, id: id) { persist() } }
    func deleteClass(_ id: CharacterClass.ID)  { if deleteCustom(from: &classes, id: id)     { persist() } }
    func deleteSubclass(_ id: Subclass.ID)     { if deleteCustom(from: &subclasses, id: id)  { persist() } }
    func deleteFeat(_ id: Feat.ID)             { if deleteCustom(from: &feats, id: id)       { persist() } }
    func deleteSpell(_ id: Spell.ID)           { if deleteCustom(from: &spells, id: id)      { persist() } }

    // MARK: - Duplication (SRD ou maison → nouvelle copie maison éditable)

    func duplicate(_ s: Species) -> Species {
        var c = s; c.isCustom = true
        c.id = uniqueID(base: s.id + "-copie", existing: species.map(\.id))
        c.name = s.name + " (copie)"
        return c
    }
    func duplicate(_ b: Background) -> Background {
        var c = b; c.isCustom = true
        c.id = uniqueID(base: b.id + "-copie", existing: backgrounds.map(\.id))
        c.name = b.name + " (copie)"
        return c
    }
    func duplicate(_ cl: CharacterClass) -> CharacterClass {
        var c = cl; c.isCustom = true
        c.id = uniqueID(base: cl.id + "-copie", existing: classes.map(\.id))
        c.name = cl.name + " (copie)"
        return c
    }
    func duplicate(_ s: Subclass) -> Subclass {
        var c = s; c.isCustom = true
        c.id = uniqueID(base: s.id + "-copie", existing: subclasses.map(\.id))
        c.name = s.name + " (copie)"
        return c
    }
    func duplicate(_ f: Feat) -> Feat {
        var c = f; c.isCustom = true
        c.id = uniqueID(base: f.id + "-copie", existing: feats.map(\.id))
        c.name = f.name + " (copie)"
        return c
    }
    func duplicate(_ s: Spell) -> Spell {
        var c = s; c.isCustom = true
        c.id = uniqueID(base: s.id + "-copie", existing: spells.map(\.id))
        c.name = s.name + " (copie)"
        return c
    }

    // MARK: - Recherche (par nom, SRD + maison)

    func searchSpecies(_ q: String)     -> [Species]        { filterByName(species, q) }
    func searchBackgrounds(_ q: String) -> [Background]     { filterByName(backgrounds, q) }
    func searchClasses(_ q: String)     -> [CharacterClass] { filterByName(classes, q) }
    func searchSubclasses(_ q: String)  -> [Subclass]       { filterByName(subclasses, q) }
    func searchFeats(_ q: String)       -> [Feat]           { filterByName(feats, q) }
    func searchSpells(_ q: String)      -> [Spell]          { filterByName(spells, q) }

    // MARK: - Import depuis un bloc JSON

    /// Type ciblé par l'import (pilote le menu déroulant de la fenêtre d'import).
    enum ImportKind: String, CaseIterable, Identifiable {
        case species    = "Espèce"
        case background = "Background"
        case characterClass = "Classe"
        case subclass   = "Sous-classe"
        case feat       = "Feat"
        var id: String { rawValue }
    }

    /// Décode un objet `{…}` OU un tableau `[…]` du type indiqué, insère le tout
    /// en maison, et renvoie le nombre d'entrées importées (ou l'erreur de décodage).
    func importJSON(_ text: String, as kind: ImportKind) -> Result<Int, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        let isArray = trimmed.hasPrefix("[")
        do {
            switch kind {
            case .species:
                let items = try decodeOneOrMany(Species.self, data, isArray)
                items.forEach { upsert($0) }; return .success(items.count)
            case .background:
                let items = try decodeOneOrMany(Background.self, data, isArray)
                items.forEach { upsert($0) }; return .success(items.count)
            case .characterClass:
                let items = try decodeOneOrMany(CharacterClass.self, data, isArray)
                items.forEach { upsert($0) }; return .success(items.count)
            case .subclass:
                let items = try decodeOneOrMany(Subclass.self, data, isArray)
                items.forEach { upsert($0) }; return .success(items.count)
            case .feat:
                let items = try decodeOneOrMany(Feat.self, data, isArray)
                items.forEach { upsert($0) }; return .success(items.count)
            }
        } catch {
            return .failure(error)
        }
    }

    private func decodeOneOrMany<T: Decodable>(_ type: T.Type, _ data: Data, _ isArray: Bool) throws -> [T] {
        let dec = JSONDecoder()
        return isArray ? try dec.decode([T].self, from: data) : [try dec.decode(T.self, from: data)]
    }

    // MARK: - Persistance des entrées maison

    /// Conteneur sérialisé : seulement les entrées maison des tableaux.
    private struct CustomContent: Codable {
        var species: [Species] = []
        var backgrounds: [Background] = []
        var classes: [CharacterClass] = []
        var subclasses: [Subclass] = []
        var feats: [Feat] = []
        var spells: [Spell] = []

        enum CodingKeys: String, CodingKey {
            case species, backgrounds, classes, subclasses, feats, spells
        }

        init(species: [Species], backgrounds: [Background], classes: [CharacterClass],
             subclasses: [Subclass], feats: [Feat], spells: [Spell]) {
            self.species = species; self.backgrounds = backgrounds; self.classes = classes
            self.subclasses = subclasses; self.feats = feats; self.spells = spells
        }

        // Décodage tolérant : chaque tableau peut manquer d'un fichier ancien.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            species     = try c.decodeIfPresent([Species].self, forKey: .species) ?? []
            backgrounds = try c.decodeIfPresent([Background].self, forKey: .backgrounds) ?? []
            classes     = try c.decodeIfPresent([CharacterClass].self, forKey: .classes) ?? []
            subclasses  = try c.decodeIfPresent([Subclass].self, forKey: .subclasses) ?? []
            feats       = try c.decodeIfPresent([Feat].self, forKey: .feats) ?? []
            spells      = try c.decodeIfPresent([Spell].self, forKey: .spells) ?? []
        }
    }

    private func loadCustom() {
        guard let url = customURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CustomContent.self, from: data) else { return }
        for s in decoded.species     { var v = s; v.isCustom = true; upsertInto(&species, v) }
        for b in decoded.backgrounds { var v = b; v.isCustom = true; upsertInto(&backgrounds, v) }
        for c in decoded.classes     { var v = c; v.isCustom = true; upsertInto(&classes, v) }
        for s in decoded.subclasses  { var v = s; v.isCustom = true; upsertInto(&subclasses, v) }
        for f in decoded.feats       { var v = f; v.isCustom = true; upsertInto(&feats, v) }
        for s in decoded.spells      { var v = s; v.isCustom = true; upsertInto(&spells, v) }
    }

    private func persist() {
        sortAll()
        guard let url = customURL else { return }
        let payload = CustomContent(
            species: species.filter(\.isCustom),
            backgrounds: backgrounds.filter(\.isCustom),
            classes: classes.filter(\.isCustom),
            subclasses: subclasses.filter(\.isCustom),
            feats: feats.filter(\.isCustom),
            spells: spells.filter(\.isCustom)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static var defaultCustomURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("CharacterApp/custom-content.json", isDirectory: false)
    }

    // MARK: - Helpers génériques

    private func upsertInto<T: Identifiable>(_ array: inout [T], _ item: T) where T.ID == String {
        if let i = array.firstIndex(where: { $0.id == item.id }) {
            array[i] = item
        } else {
            array.append(item)
        }
    }

    /// Retire une entrée maison du tableau. Renvoie `true` si une suppression a
    /// eu lieu. NE PERSISTE PAS ici (l'appelant le fait une fois l'inout relâché).
    @discardableResult
    private func deleteCustom<T>(from array: inout [T], id: String) -> Bool
        where T: Identifiable, T.ID == String, T: HasCustomFlag {
        guard let i = array.firstIndex(where: { $0.id == id }), array[i].isCustom else { return false }
        array.remove(at: i)
        return true
    }

    private func uniqueID(base: String, existing: [String]) -> String {
        let set = Set(existing)
        if !set.contains(base) { return base }
        var n = 2
        while set.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private func filterByName<T: NamedEntity>(_ array: [T], _ query: String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return array }
        return array.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func sortAll() {
        species.sort     { $0.name.localizedCompare($1.name) == .orderedAscending }
        backgrounds.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        classes.sort     { $0.name.localizedCompare($1.name) == .orderedAscending }
        subclasses.sort  { $0.name.localizedCompare($1.name) == .orderedAscending }
        feats.sort       { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Conformances utilitaires (permettent les helpers génériques ci-dessus)

protocol HasCustomFlag { var isCustom: Bool { get } }
protocol NamedEntity { var name: String { get } }

extension Species: HasCustomFlag, NamedEntity {}
extension Background: HasCustomFlag, NamedEntity {}
extension CharacterClass: HasCustomFlag, NamedEntity {}
extension Subclass: HasCustomFlag, NamedEntity {}
extension Feat: HasCustomFlag, NamedEntity {}
extension Spell: HasCustomFlag, NamedEntity {}

// MARK: - Amorçage (repli si les JSON SRD sont absents du bundle)

extension ContentLibrary {

    /// Jeu minimal en mémoire, identique à l'ancien `.seed`, utilisé seulement
    /// quand les ressources SRD ne sont pas présentes (aperçus, tests).
    static var seed: (species: [Species], backgrounds: [Background],
                      classes: [CharacterClass], subclasses: [Subclass], feats: [Feat]) {
        let species = [
            Species(id: "humain", name: "Humaine", traits: [
                Trait(name: "Polyvalente", description: "Origin feat (free choice)."),
                Trait(name: "Skill", description: "Maîtrise d'un skill supplémentaire."),
                Trait(name: "Ingénieuse", description: "Inspiration héroïque à chaque repos long.")
            ]),
            Species(id: "nain-des-collines", name: "Nain des collines", traits: [
                Trait(name: "Vision dans le noir", description: "18 m."),
                Trait(name: "Résistance naine", description: "Avantage et résistance contre le poison."),
                Trait(name: "Robustesse naine", description: "+1 PV par niveau.")
            ], woundBonus: 12)
        ]
        let backgrounds = [
            Background(id: "sage", name: "Sage",
                       abilityOptions: [.CON, .INT, .WIS],
                       skillProficiencies: [.arcanes, .histoire],
                       originFeatId: "initie-magie",
                       toolProficiency: "Matériel de calligraphe",
                       equipmentText: "Bâton, robe, livre, encre et plume, 8 po"),
            Background(id: "soldat", name: "Soldat",
                       abilityOptions: [.STR, .DEX, .CON],
                       skillProficiencies: [.athletisme, .intimidation],
                       originFeatId: "tueur-sauvage",
                       toolProficiency: "Un type de jeu (au choix)",
                       equipmentText: "Lance, épée courte, jeu de dés, 14 po")
        ]
        let classes = [
            CharacterClass(id: "clerc", name: "Clerc", hitDie: "d8",
                           saveProficiencies: [.WIS, .CHA],
                           casterType: .full, spellcastingAbility: .WIS,
                           skillChoiceCount: 2,
                           skillChoiceOptions: [.histoire, .intuition, .medecine, .persuasion, .religion],
                           asiLevels: [4, 8, 12, 16, 19],
                           features: [
                               Trait(name: "Incantation", description: "Lance des sorts de clerc (SAG).", level: 1),
                               Trait(name: "Ordre divin", description: "Protecteur ou Penseur.", level: 1),
                               Trait(name: "Canaliser la divinité", description: "Renvoi des morts, Étincelle divine.", level: 2)
                           ]),
            CharacterClass(id: "guerrier", name: "Guerrier", hitDie: "d10",
                           saveProficiencies: [.STR, .CON],
                           casterType: .none, spellcastingAbility: nil,
                           skillChoiceCount: 2,
                           skillChoiceOptions: [.acrobaties, .athletisme, .dressage, .histoire,
                                                .intuition, .intimidation, .perception, .survie],
                           asiLevels: [4, 6, 8, 12, 14, 16, 19],
                           features: [
                               Trait(name: "Style de combat", description: "Un style au choix.", level: 1),
                               Trait(name: "Second souffle", description: "Récupère des PV (bonus).", level: 1),
                               Trait(name: "Attaque supplémentaire", description: "Deux attaques par action.", level: 5)
                           ])
        ]
        let subclasses = [
            Subclass(id: "domaine-de-la-vie", name: "Domaine de la Vie", parentClassId: "clerc",
                     features: [
                        Trait(name: "Disciple de la vie", description: "Soins majorés.", level: 3),
                        Trait(name: "Bénédiction du soigneur", description: "Soins à soi-même.", level: 6)
                     ]),
            Subclass(id: "champion", name: "Champion", parentClassId: "guerrier",
                     features: [
                        Trait(name: "Critique amélioré", description: "Critique sur 19-20.", level: 3)
                     ])
        ]
        let feats = [
            Feat(id: "initie-magie", name: "Initié à la magie (clerc)", category: .origin,
                 shortEffect: "Deux tours de magie et un sort de niveau 1 par repos long."),
            Feat(id: "alerte", name: "Alerte", category: .origin,
                 shortEffect: "Ajoute le bonus de maîtrise à l'initiative."),
            Feat(id: "tueur-sauvage", name: "Tueur sauvage", category: .origin,
                 shortEffect: "Relance les dés de dégâts d'arme une fois par tour.")
        ]
        return (species, backgrounds, classes, subclasses, feats)
    }
}
