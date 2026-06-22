import Foundation

// =====================================================================
//  CharacterModels.swift
//  Modèles de données de l'app de création de personnages (D&D 5e / SRD 5.2).
//  Couche pure (aucune dépendance UI), compilable et testable seule.
// =====================================================================

// MARK: - Primitives partagées avec l'app de combat
// App séparée : ces trois types sont recopiés à l'identique depuis l'app de
// combat (sauf `Trait`, qui reçoit ici un `level` optionnel). Si ce fichier
// vivait un jour dans le même target que l'app de combat, supprimer ce bloc.

/// Les six caractéristiques (codes anglais SRD).
enum Ability: String, Codable, CaseIterable {
    case STR, DEX, CON, INT, WIS, CHA
}

/// Scores des six caractéristiques + dérivation des modificateurs.
struct AbilityScores: Codable, Equatable {
    var STR: Int
    var DEX: Int
    var CON: Int
    var INT: Int
    var WIS: Int
    var CHA: Int

    func score(_ a: Ability) -> Int {
        switch a {
        case .STR: return STR
        case .DEX: return DEX
        case .CON: return CON
        case .INT: return INT
        case .WIS: return WIS
        case .CHA: return CHA
        }
    }

    /// Modificateur D&D 5e : (score − 10) / 2, arrondi vers le bas.
    func modifier(_ a: Ability) -> Int {
        Int(floor(Double(score(a) - 10) / 2.0))
    }
}

/// Capacité descriptive. `level` = niveau d'obtention pour les capacités de
/// classe / sous-classe ; nil pour un trait permanent (espèce).
struct Trait: Codable {
    var name: String
    var description: String
    var level: Int? = nil
}

// MARK: - Compétences

/// Les 18 compétences. La rawValue (libellé accentué) sert d'identifiant JSON
/// et d'affichage, pour coller aux exemples de la spécification.
enum Skill: String, Codable, CaseIterable {
    case acrobaties     = "Acrobatics"
    case arcanes        = "Arcana"
    case athletisme     = "Athletics"
    case discretion     = "Stealth"
    case dressage       = "Animal Handling"
    case escamotage     = "Sleight of Hand"
    case histoire       = "History"
    case intimidation   = "Intimidation"
    case intuition      = "Insight"
    case investigation  = "Investigation"
    case medecine       = "Medicine"
    case nature         = "Nature"
    case perception     = "Perception"
    case persuasion     = "Persuasion"
    case religion       = "Religion"
    case representation = "Performance"
    case survie         = "Survival"
    case tromperie      = "Deception"

    /// Caractéristique régissante.
    var ability: Ability {
        switch self {
        case .athletisme:
            return .STR
        case .acrobaties, .discretion, .escamotage:
            return .DEX
        case .arcanes, .histoire, .investigation, .nature, .religion:
            return .INT
        case .dressage, .intuition, .medecine, .perception, .survie:
            return .WIS
        case .intimidation, .persuasion, .representation, .tromperie:
            return .CHA
        }
    }

    /// Libellé affiché (rawValue anglais).
    var label: String { rawValue }

    /// Toutes les compétences triées par libellé anglais (pour l'affichage).
    static var allCasesSorted: [Skill] {
        allCases.sorted { $0.label < $1.label }
    }
}

// MARK: - Feats

enum FeatCategory: String, Codable, CaseIterable {
    case general            // e.g. Grappler
    case origin             // origin feats (Alert, Magic Initiate…)
    case fightingStyle      // fighting styles (Archery, Defense…)
    case epicBoon           // epic boons (level 19+)
}

/// Un don. Aucun effet mécanique sauf le +1 de caractéristique éventuel.
struct Feat: Codable, Identifiable {
    var id: String
    var name: String
    var category: FeatCategory
    var shortEffect: String
    /// Prérequis éventuel (ex. « niveau 4+ », « Force 13 »). Vide = aucun.
    var prerequisite: String = ""
    /// Caractéristiques éligibles au +1 accordé par ce don. Vide = aucun bonus ;
    /// une seule = stat imposée ; plusieurs = choix ; les six = choix libre.
    var abilityBonusOptions: [Ability] = []
    var isCustom: Bool = false

    init(id: String, name: String, category: FeatCategory, shortEffect: String,
         prerequisite: String = "", abilityBonusOptions: [Ability] = [], isCustom: Bool = false) {
        self.id = id; self.name = name; self.category = category
        self.shortEffect = shortEffect; self.prerequisite = prerequisite
        self.abilityBonusOptions = abilityBonusOptions; self.isCustom = isCustom
    }

    // Décodage tolérant : `prerequisite`, `abilityBonusOptions` et `isCustom`
    // peuvent manquer du JSON (le Codable synthétisé exigerait la clé).
    enum CodingKeys: String, CodingKey {
        case id, name, category, shortEffect, prerequisite, abilityBonusOptions, isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(FeatCategory.self, forKey: .category)
        shortEffect = try c.decode(String.self, forKey: .shortEffect)
        prerequisite = try c.decodeIfPresent(String.self, forKey: .prerequisite) ?? ""
        abilityBonusOptions = try c.decodeIfPresent([Ability].self, forKey: .abilityBonusOptions) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

// MARK: - Espèce

struct Species: Codable, Identifiable {
    var id: String
    var name: String
    var traits: [Trait]
    /// Valeur statique de blessures liée à la robustesse de l'espèce.
    /// wounds = score de CON + woundBonus. 10 = humanoïde standard,
    /// 12 = espèce robuste (nain, goliath…), 8 = espèce frêle (elfe, halfelin…).
    var woundBonus: Int = 10
    var isCustom: Bool = false
    // Rappel : en 2024, l'espèce ne donne aucun bonus de caractéristique.

    // Init membre explicite : conservé car plusieurs sites construisent
    // Species(...) directement (seed, aperçus, éditeur de bibliothèque).
    init(id: String, name: String, traits: [Trait],
         woundBonus: Int = 10, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.traits = traits
        self.woundBonus = woundBonus
        self.isCustom = isCustom
    }

    // Décodage rétro-compatible : woundBonus & isCustom peuvent manquer dans
    // les données déjà persistées. Sans decodeIfPresent, l'échec d'un seul
    // objet (try? sur le tableau complet) effacerait tout le contenu.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        traits = try c.decode([Trait].self, forKey: .traits)
        woundBonus = try c.decodeIfPresent(Int.self, forKey: .woundBonus) ?? 10
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

// MARK: - Historique

struct Background: Codable, Identifiable {
    var id: String
    var name: String
    /// Caracs recommandées par le SRD (informatif : le placement reste libre).
    var abilityOptions: [Ability]
    /// Compétences maîtrisées fixes (en général 2).
    var skillProficiencies: [Skill]
    /// Don d'origine (référence la bibliothèque de dons).
    var originFeatId: String?
    var toolProficiency: String
    var equipmentText: String
    var isCustom: Bool = false

    /// Sentinelle vide : évite les crash quand la bibliothèque n'est pas encore chargée.
    static let empty = Background(
        id: "", name: "—", abilityOptions: [],
        skillProficiencies: [], originFeatId: nil,
        toolProficiency: "", equipmentText: ""
    )
}

// MARK: - Classe & sous-classe

enum CasterType: String, Codable, CaseIterable {
    case none       // non-lanceur
    case full       // lanceur complet
    case half       // demi-lanceur (à partir du niveau 2)
    case third      // tiers-lanceur (hors SRD ; contenu maison)
    case pact       // Magie de pacte (Démoniste)
}

struct CharacterClass: Codable, Identifiable {
    var id: String
    var name: String
    /// Le dé (ex. « d8 ») : sert au pool de dés de vie, pas au calcul des PV.
    var hitDie: String
    /// Les deux sauvegardes maîtrisées de la classe.
    var saveProficiencies: [Ability]
    var casterType: CasterType
    var spellcastingAbility: Ability?
    /// Règle de choix de compétences : « N parmi `skillChoiceOptions` ».
    var skillChoiceCount: Int
    var skillChoiceOptions: [Skill]
    /// Niveaux d'amélioration de caractéristique (défaut [4,8,12,16,19]).
    var asiLevels: [Int]
    /// Tables de sorts par niveau (index 0 = niveau 1, 20 entrées). Vide si non applicable.
    var cantripsKnownByLevel: [Int] = []
    var preparedSpellsByLevel: [Int] = []
    /// Capacités, chacune portant son `level` d'obtention.
    var features: [Trait]
    var isCustom: Bool = false

    /// Sentinelle vide : évite les crash quand la bibliothèque n'est pas encore chargée.
    static let empty = CharacterClass(
        id: "", name: "—", hitDie: "d8",
        saveProficiencies: [], casterType: .none,
        spellcastingAbility: nil, skillChoiceCount: 0,
        skillChoiceOptions: [], asiLevels: [],
        cantripsKnownByLevel: [], preparedSpellsByLevel: [],
        features: []
    )
}

struct Subclass: Codable, Identifiable {
    var id: String
    var name: String
    var parentClassId: String
    var features: [Trait]
    var isCustom: Bool = false
}

/// Sort « léger » : nom + niveau + classes qui peuvent l'apprendre (sans description).
/// `level == 0` désigne un sort mineur (cantrip).
struct Spell: Codable, Identifiable {
    var id: String
    var name: String
    var level: Int
    var classIds: [String]
    var isCustom: Bool = false
}

/// Outil « léger » : nom seulement (artisan ou kit, sans distinction).
/// Les instruments de musique et les jeux sont volontairement exclus du jeu de données.
struct Tool: Codable, Identifiable {
    var id: String
    var name: String
    /// Conservé pour compatibilité du JSON ; toujours "tool" désormais.
    var category: String = "tool"
    var isCustom: Bool = false
}

/// Élément d'équipement « léger » (arme, armure, équipement général).
/// `group` sert d'en-tête de section pour l'affichage (parallèle à `Spell.level`).
/// `detail` = stats courtes (dégâts/CA + propriétés) ; `weight` = poids formaté.
struct EquipmentItem: Codable, Identifiable {
    var id: String
    var name: String
    var group: String
    var detail: String = ""
    var weight: String = ""
    var isCustom: Bool = false

    init(id: String, name: String, group: String,
         detail: String = "", weight: String = "", isCustom: Bool = false) {
        self.id = id; self.name = name; self.group = group
        self.detail = detail; self.weight = weight; self.isCustom = isCustom
    }

    // Décodage tolérant : `detail`/`weight`/`isCustom` peuvent manquer du JSON.
    enum CodingKeys: String, CodingKey { case id, name, group, detail, weight, isCustom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        group = try c.decode(String.self, forKey: .group)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        weight = try c.decodeIfPresent(String.self, forKey: .weight) ?? ""
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

// MARK: - Choix du personnage

/// Une source de bonus de caractéristique (historique ou amélioration de niveau).
/// Placement libre ; l'éditeur valide le motif (`{+2,+1}` / `{+1,+1,+1}` à la
/// création ; `{+2}` / `{+1,+1}` par niveau).
struct AbilityIncrease: Codable, Equatable {
    var source: String
    var allocations: [Ability: Int]

    init(source: String, allocations: [Ability: Int]) {
        self.source = source
        self.allocations = allocations
    }

    // Codable manuel : `[Ability: Int]` doit s'encoder en objet JSON
    // ({"STR": 2, "CON": 1}) et non en tableau alterné clé/valeur.
    enum CodingKeys: String, CodingKey { case source, allocations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        let raw = try c.decode([String: Int].self, forKey: .allocations)
        var dict: [Ability: Int] = [:]
        for (key, value) in raw {
            if let a = Ability(rawValue: key) { dict[a] = value }
        }
        allocations = dict
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        var raw: [String: Int] = [:]
        for (a, value) in allocations { raw[a.rawValue] = value }
        try c.encode(raw, forKey: .allocations)
    }
}

/// Un don pris à un niveau d'amélioration (le don d'origine de l'historique, lui,
/// est automatique via `Background.originFeatId`).
struct FeatChoice: Codable, Equatable {
    var source: String
    var featId: String
    /// Caractéristique recevant le +1 quand le don en accorde un (nil sinon).
    /// Propriété Optional → le Codable synthétisé tolère son absence du JSON.
    var abilityBonus: Ability? = nil
}

/// Trois pièces propres à la campagne (Thalaris), comptées indépendamment.
struct Currency: Codable, Equatable {
    var aureon: Int = 0
    var solari: Int = 0
    var scaille: Int = 0
}

// MARK: - Personnage

struct Character: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var playerName: String = ""

    var speciesId: String
    var backgroundId: String
    var classId: String
    var subclassId: String?
    var level: Int

    var baseAbilities: AbilityScores
    var abilityIncreases: [AbilityIncrease] = []
    var chosenClassSkills: [Skill] = []
    var expertise: [Skill] = []
    var featChoices: [FeatChoice] = []

    // Santé & combat — valeurs calculées + ajustement manuel (bonus signé).
    // Les totaux affichés = base calculée (SheetBuilder) + ces offsets.
    var hitPointsBonus: Int = 0
    var armorClassBonus: Int = 0
    var initiativeBonus: Int = 0
    var bloodied: Bool = false
    var deathSaveSuccesses: Int = 0
    var deathSaveFailures: Int = 0
    var hitDiceUsed: Int = 0

    // Texte libre
    var equipmentText: String = ""
    var currency: Currency = Currency()
    var notesText: String = ""

    // Sorts du SRD cochés (clés de Spell). Le texte libre ci-dessus reste pour les sorts maison.
    var knownSpellIds: [String] = []

    // Outils du SRD choisis (clés de Tool). L'outil fixe de l'historique
    // (Background.toolProficiency, texte libre) reste affiché séparément.
    var chosenToolIds: [String] = []

    // Équipement possédé (clés des catalogues EquipmentItem / Tool). Distinct des
    // maîtrises : ce que le personnage POSSÈDE, pas ce avec quoi il est compétent.
    // Le texte libre `equipmentText` reste pour les objets hors catalogue.
    var ownedWeaponIds: [String] = []
    var ownedArmorIds: [String] = []
    var ownedToolIds: [String] = []
    var ownedGearIds: [String] = []
}

// MARK: - Décodage tolérant de Character
// Le Codable synthétisé exige TOUTES les clés : un personnage sauvegardé avant
// l'ajout d'un champ ferait alors échouer le décodage de toute la liste
// (`CharacterStore.load` fait `try?`, donc perte silencieuse totale). On décode
// donc en `decodeIfPresent`. Placé en extension pour conserver l'initialiseur
// membre à membre utilisé par `CharacterStore.newCharacter`.
extension Character {
    enum CodingKeys: String, CodingKey {
        case id, name, playerName, speciesId, backgroundId, classId, subclassId, level
        case baseAbilities, abilityIncreases, chosenClassSkills, expertise, featChoices
        case armorClassBonus, hitPointsBonus, initiativeBonus, bloodied
        case deathSaveSuccesses, deathSaveFailures, hitDiceUsed
        case equipmentText, currency, notesText
        case knownSpellIds, chosenToolIds
        case ownedWeaponIds, ownedArmorIds, ownedToolIds, ownedGearIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name          = try c.decode(String.self, forKey: .name)
        playerName    = try c.decodeIfPresent(String.self, forKey: .playerName) ?? ""
        speciesId     = try c.decode(String.self, forKey: .speciesId)
        backgroundId  = try c.decode(String.self, forKey: .backgroundId)
        classId       = try c.decode(String.self, forKey: .classId)
        subclassId    = try c.decodeIfPresent(String.self, forKey: .subclassId)
        level         = try c.decode(Int.self, forKey: .level)
        baseAbilities = try c.decode(AbilityScores.self, forKey: .baseAbilities)
        abilityIncreases  = try c.decodeIfPresent([AbilityIncrease].self, forKey: .abilityIncreases) ?? []
        chosenClassSkills = try c.decodeIfPresent([Skill].self, forKey: .chosenClassSkills) ?? []
        expertise         = try c.decodeIfPresent([Skill].self, forKey: .expertise) ?? []
        featChoices       = try c.decodeIfPresent([FeatChoice].self, forKey: .featChoices) ?? []
        armorClassBonus = try c.decodeIfPresent(Int.self, forKey: .armorClassBonus) ?? 0
        hitPointsBonus  = try c.decodeIfPresent(Int.self, forKey: .hitPointsBonus) ?? 0
        initiativeBonus = try c.decodeIfPresent(Int.self, forKey: .initiativeBonus) ?? 0
        bloodied        = try c.decodeIfPresent(Bool.self, forKey: .bloodied) ?? false
        deathSaveSuccesses = try c.decodeIfPresent(Int.self, forKey: .deathSaveSuccesses) ?? 0
        deathSaveFailures  = try c.decodeIfPresent(Int.self, forKey: .deathSaveFailures) ?? 0
        hitDiceUsed        = try c.decodeIfPresent(Int.self, forKey: .hitDiceUsed) ?? 0
        equipmentText  = try c.decodeIfPresent(String.self, forKey: .equipmentText) ?? ""
        currency       = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        notesText      = try c.decodeIfPresent(String.self, forKey: .notesText) ?? ""
        knownSpellIds  = try c.decodeIfPresent([String].self, forKey: .knownSpellIds) ?? []
        chosenToolIds  = try c.decodeIfPresent([String].self, forKey: .chosenToolIds) ?? []
        ownedWeaponIds = try c.decodeIfPresent([String].self, forKey: .ownedWeaponIds) ?? []
        ownedArmorIds  = try c.decodeIfPresent([String].self, forKey: .ownedArmorIds) ?? []
        ownedToolIds   = try c.decodeIfPresent([String].self, forKey: .ownedToolIds) ?? []
        ownedGearIds   = try c.decodeIfPresent([String].self, forKey: .ownedGearIds) ?? []
    }
}
