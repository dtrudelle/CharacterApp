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

/// Un don. Aucun effet mécanique : on affiche seulement nom + effet abrégé.
struct Feat: Codable, Identifiable {
    var id: String
    var name: String
    var category: FeatCategory
    var shortEffect: String
    /// Prérequis éventuel (ex. « niveau 4+ », « Force 13 »). Vide = aucun.
    var prerequisite: String = ""
    var isCustom: Bool = false

    init(id: String, name: String, category: FeatCategory, shortEffect: String,
         prerequisite: String = "", isCustom: Bool = false) {
        self.id = id; self.name = name; self.category = category
        self.shortEffect = shortEffect; self.prerequisite = prerequisite; self.isCustom = isCustom
    }

    // Décodage tolérant : `prerequisite` et `isCustom` peuvent manquer du JSON
    // (le Codable synthétisé, lui, exigerait la clé même avec une valeur par défaut).
    enum CodingKeys: String, CodingKey { case id, name, category, shortEffect, prerequisite, isCustom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(FeatCategory.self, forKey: .category)
        shortEffect = try c.decode(String.self, forKey: .shortEffect)
        prerequisite = try c.decodeIfPresent(String.self, forKey: .prerequisite) ?? ""
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

// MARK: - Espèce

struct Species: Codable, Identifiable {
    var id: String
    var name: String
    var traits: [Trait]
    var isCustom: Bool = false
    // Rappel : en 2024, l'espèce ne donne aucun bonus de caractéristique.
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

    // Santé & combat — saisis ou suivis manuellement
    var armorClassText: String = ""
    var hitPointsText: String = ""
    var initiativeText: String = ""
    var bloodied: Bool = false
    var deathSaveSuccesses: Int = 0
    var deathSaveFailures: Int = 0
    var hitDiceUsed: Int = 0

    // Texte libre
    var spellListText: String = ""
    var equipmentText: String = ""
    var currency: Currency = Currency()
    var notesText: String = ""

    // Sorts du SRD cochés (clés de Spell). Le texte libre ci-dessus reste pour les sorts maison.
    var knownSpellIds: [String] = []

    // Outils du SRD choisis (clés de Tool). L'outil fixe de l'historique
    // (Background.toolProficiency, texte libre) reste affiché séparément.
    var chosenToolIds: [String] = []
}
