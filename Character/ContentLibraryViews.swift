import SwiftUI

// =====================================================================
//  ContentLibraryViews.swift
//  Fenêtres « Bibliothèque » du module de fiches de personnage.
//  Pour chacun des cinq types (espèce, historique, classe, sous-classe, don) :
//   • une fenêtre bibliothèque (liste SRD + maison, recherche, badge maison,
//     dupliquer / éditer / supprimer sur les maison, bouton « Nouveau ») ;
//   • un éditeur sur feuille, privilégiant les menus déroulants.
//  Plus une fenêtre d'import unique avec menu déroulant de type.
//
//  Calqué sur MonsterLibrarySheet / MonsterEditorSheet (module combat).
// =====================================================================

// MARK: - Composants partagés

/// Badge « maison » affiché à côté des entrées éditables.
private struct CustomBadge: View {
    var body: some View {
        Text("maison")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.20)))
    }
}

/// Menu déroulant à choix unique d'une caractéristique (ou « aucune »).
private struct AbilityPicker: View {
    let title: String
    @Binding var value: Ability?
    var allowsNone: Bool = false

    var body: some View {
        Picker(title, selection: $value) {
            if allowsNone { Text("Aucune").tag(Ability?.none) }
            ForEach(Ability.allCases, id: \.self) { a in
                Text(a.rawValue).tag(Ability?.some(a))
            }
        }
    }
}

/// Menu déroulant à choix multiple de caractéristiques.
private struct AbilityMultiMenu: View {
    let title: String
    @Binding var values: [Ability]

    var body: some View {
        LabeledContent(title) {
            Menu {
                ForEach(Ability.allCases, id: \.self) { a in
                    Toggle(a.rawValue, isOn: binding(for: a))
                }
            } label: {
                Text(values.isEmpty ? "Aucune" : values.map(\.rawValue).joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func binding(for a: Ability) -> Binding<Bool> {
        Binding(
            get: { values.contains(a) },
            set: { on in
                if on { if !values.contains(a) { values.append(a) } }
                else { values.removeAll { $0 == a } }
            }
        )
    }
}

/// Menu déroulant à choix multiple de compétences (les 18 du SRD).
private struct SkillMultiMenu: View {
    let title: String
    @Binding var values: [Skill]

    var body: some View {
        LabeledContent(title) {
            Menu {
                ForEach(Skill.allCases, id: \.self) { s in
                    Toggle(s.label, isOn: binding(for: s))
                }
                if !values.isEmpty {
                    Divider()
                    Button("Tout effacer", role: .destructive) { values = [] }
                }
            } label: {
                Text(values.isEmpty ? "Aucune" : values.map(\.label).joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func binding(for s: Skill) -> Binding<Bool> {
        Binding(
            get: { values.contains(s) },
            set: { on in
                if on { if !values.contains(s) { values.append(s) } }
                else { values.removeAll { $0 == s } }
            }
        )
    }
}

/// Éditeur de liste de capacités/traits (réutilisé par espèce/classe/sous-classe).
/// `withLevel` affiche un champ de niveau d'obtention (classes & sous-classes).
private struct TraitsEditor: View {
    @Binding var rows: [TraitRow]
    var withLevel: Bool

    var body: some View {
        ForEach($rows) { $row in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Nom de la capacité", text: $row.name)
                    if withLevel {
                        Picker("Niveau", selection: levelBinding(for: $row)) {
                            ForEach(1...20, id: \.self) { Text("Niv. \($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == row.id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
                TextField("Description", text: $row.description, axis: .vertical)
                    .lineLimit(1...5)
            }
            .padding(.vertical, 2)
        }
        Button { rows.append(TraitRow(defaultLevel: withLevel ? 1 : nil)) } label: {
            Label("Ajouter une capacité", systemImage: "plus")
        }
        .controlSize(.small)
    }

    /// Le Picker travaille sur un Int non optionnel ; on mappe vers/depuis `level?`.
    private func levelBinding(for row: Binding<TraitRow>) -> Binding<Int> {
        Binding(
            get: { row.wrappedValue.level ?? 1 },
            set: { row.wrappedValue.level = $0 }
        )
    }
}

/// Ligne éditable de trait/capacité (modèle de brouillon local à l'UI).
struct TraitRow: Identifiable {
    let id = UUID()
    var name: String = ""
    var description: String = ""
    var level: Int? = nil

    func toTrait() -> Trait { Trait(name: name, description: description, level: level) }
    init() {}
    init(defaultLevel: Int?) { level = defaultLevel }
    init(_ t: Trait) { name = t.name; description = t.description; level = t.level }
}

/// Slugifie un nom en identifiant maison stable (sans collision via la lib).
private func makeID(from name: String, prefix: String) -> String {
    let base = name.folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let slug = base.isEmpty ? UUID().uuidString.prefix(8).lowercased() : base
    return "\(prefix)-\(slug)"
}

// =====================================================================
//  ESPÈCES
// =====================================================================

struct SpeciesLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: Species?

    var body: some View {
        LibraryScaffold(
            title: "Espèces",
            subtitle: "Dupliquez ou créez une espèce maison. Les entrées SRD restent intactes.",
            query: $query,
            onNew: { editing = Species(id: "", name: "Nouvelle espèce", traits: [], isCustom: true) },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchSpecies(query)) { sp in
                EntryRow(
                    name: sp.name,
                    detail: "\(sp.traits.count) trait·s",
                    isCustom: sp.isCustom,
                    onDuplicate: { let c = library.duplicate(sp); library.upsert(c); editing = c },
                    onEdit: { editing = sp },
                    onDelete: { library.deleteSpecies(sp.id) }
                )
            }
        }
        .sheet(item: $editing) { sp in SpeciesEditorSheet(species: sp) }
    }
}

struct SpeciesEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Species
    @State private var traits: [TraitRow]

    init(species: Species) {
        _draft = State(initialValue: species)
        _traits = State(initialValue: species.traits.map { TraitRow($0) })
    }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                }
                Section("Traits (en 2024, l'espèce ne donne aucun bonus de carac)") {
                    TraitsEditor(rows: $traits, withLevel: false)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "esp") }
        draft.traits = traits.map { $0.toTrait() }
        library.upsert(draft)
        dismiss()
    }
}

// =====================================================================
//  HISTORIQUES
// =====================================================================

struct BackgroundLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: Background?

    var body: some View {
        LibraryScaffold(
            title: "Backgrounds",
            subtitle: "Dupliquez ou créez un historique maison.",
            query: $query,
            onNew: {
                editing = Background(id: "", name: "Nouvel historique",
                                     abilityOptions: [], skillProficiencies: [],
                                     originFeatId: nil, toolProficiency: "",
                                     equipmentText: "", isCustom: true)
            },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchBackgrounds(query)) { bg in
                EntryRow(
                    name: bg.name,
                    detail: bg.skillProficiencies.map(\.label).joined(separator: ", "),
                    isCustom: bg.isCustom,
                    onDuplicate: { let c = library.duplicate(bg); library.upsert(c); editing = c },
                    onEdit: { editing = bg },
                    onDelete: { library.deleteBackground(bg.id) }
                )
            }
        }
        .sheet(item: $editing) { bg in BackgroundEditorSheet(background: bg) }
    }
}

/// Mode de saisie de la maîtrise d'outil d'un historique :
/// « Liste » = choix dans la liste des outils (recommandé : garantit le lien
/// automatique avec l'éditeur de personnage, qui coche l'outil par nom exact) ;
/// « Texte libre » = valeurs hors liste (ex. « un jeu de société au choix »).
private enum ToolEntryMode: String, CaseIterable, Identifiable {
    case tool = "Liste"
    case free = "Texte libre"
    var id: String { rawValue }
}

struct BackgroundEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Background
    @State private var abilityOptions: [Ability]
    @State private var skills: [Skill]
    @State private var originFeatId: String   // "" = aucun
    @State private var toolMode: ToolEntryMode = .tool

    init(background: Background) {
        _draft = State(initialValue: background)
        _abilityOptions = State(initialValue: background.abilityOptions)
        _skills = State(initialValue: background.skillProficiencies)
        _originFeatId = State(initialValue: background.originFeatId ?? "")
    }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                }
                Section("Caractéristiques & Skill") {
                    AbilityMultiMenu(title: "Caracs recommandées", values: $abilityOptions)
                    SkillMultiMenu(title: "Maîtrises de skill", values: $skills)
                }
                Section("Origin Feat") {
                    // Référence un don existant : menu déroulant (évite les fautes de frappe).
                    Picker("Origin Feat", selection: $originFeatId) {
                        Text("Aucun").tag("")
                        ForEach(library.feats) { f in Text(f.name).tag(f.id) }
                    }
                }
                Section("Divers") {
                    Picker("Maîtrise d'outil", selection: $toolMode) {
                        ForEach(ToolEntryMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if toolMode == .tool {
                        // Le menu écrit le nom exact de l'outil → l'éditeur de
                        // personnage coche l'outil automatiquement (cf. toolMatch).
                        Picker("Outil", selection: toolNameBinding) {
                            Text("Aucun").tag("")
                            ForEach(library.tools) { t in Text(t.name).tag(t.name) }
                        }
                    } else {
                        TextField("Maîtrise d'outil (texte libre)", text: $draft.toolProficiency)
                    }
                    TextField("Équipement (texte)", text: $draft.equipmentText, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .formStyle(.grouped)
            .onAppear {
                // Texte libre seulement si la valeur existante ne correspond à
                // aucun outil connu (ex. historique custom déjà saisi à la main).
                let raw = draft.toolProficiency
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let known = library.tools.contains { $0.name.lowercased() == raw }
                toolMode = (raw.isEmpty || known) ? .tool : .free
            }
        }
    }

    /// Lit/écrit `draft.toolProficiency` en mode liste : le getter renvoie le nom
    /// canonique de l'outil si la valeur courante correspond (insensible à la casse)
    /// à un outil connu, sinon "" (→ « Aucun »). Le setter stocke le nom exact.
    private var toolNameBinding: Binding<String> {
        Binding(
            get: {
                let raw = draft.toolProficiency
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return library.tools.first { $0.name.lowercased() == raw }?.name ?? ""
            },
            set: { draft.toolProficiency = $0 }
        )
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "hist") }
        draft.abilityOptions = abilityOptions
        draft.skillProficiencies = skills
        draft.originFeatId = originFeatId.isEmpty ? nil : originFeatId
        library.upsert(draft)
        dismiss()
    }
}

// =====================================================================
//  CLASSES
// =====================================================================

private let hitDice = ["d6", "d8", "d10", "d12"]

struct ClassLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: CharacterClass?

    var body: some View {
        LibraryScaffold(
            title: "Classes",
            subtitle: "Dupliquez ou créez une classe maison.",
            query: $query,
            onNew: {
                editing = CharacterClass(id: "", name: "Nouvelle classe", hitDie: "d8",
                                         saveProficiencies: [], casterType: .none,
                                         spellcastingAbility: nil, skillChoiceCount: 2,
                                         skillChoiceOptions: [], asiLevels: [4, 8, 12, 16, 19],
                                         features: [], isCustom: true)
            },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchClasses(query)) { cl in
                EntryRow(
                    name: cl.name,
                    detail: "\(cl.hitDie) · \(cl.casterType.rawValue)",
                    isCustom: cl.isCustom,
                    onDuplicate: { let c = library.duplicate(cl); library.upsert(c); editing = c },
                    onEdit: { editing = cl },
                    onDelete: { library.deleteClass(cl.id) }
                )
            }
        }
        .sheet(item: $editing) { cl in ClassEditorSheet(characterClass: cl) }
    }
}

struct ClassEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CharacterClass
    @State private var saves: [Ability]
    @State private var spellAbility: Ability?
    @State private var skillOptions: [Skill]
    @State private var asiText: String
    @State private var features: [TraitRow]

    init(characterClass: CharacterClass) {
        _draft = State(initialValue: characterClass)
        _saves = State(initialValue: characterClass.saveProficiencies)
        _spellAbility = State(initialValue: characterClass.spellcastingAbility)
        _skillOptions = State(initialValue: characterClass.skillChoiceOptions)
        _asiText = State(initialValue: characterClass.asiLevels.map(String.init).joined(separator: ", "))
        _features = State(initialValue: characterClass.features.map { TraitRow($0) })
    }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                    Picker("Dé de vie", selection: $draft.hitDie) {
                        ForEach(hitDice, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Sauvegardes & incantation") {
                    AbilityMultiMenu(title: "Sauvegardes maîtrisées", values: $saves)
                    Picker("Type de lanceur", selection: $draft.casterType) {
                        ForEach(CasterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    AbilityPicker(title: "Carac d'incantation", value: $spellAbility, allowsNone: true)
                }
                Section("Skill") {
                    Stepper("Nombre à choisir : \(draft.skillChoiceCount)",
                            value: $draft.skillChoiceCount, in: 0...6)
                    SkillMultiMenu(title: "Choix possibles", values: $skillOptions)
                }
                Section("Améliorations de carac (niveaux, séparés par des virgules)") {
                    TextField("ex. 4, 8, 12, 16, 19", text: $asiText)
                }
                Section("Capacités") {
                    TraitsEditor(rows: $features, withLevel: true)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "classe") }
        draft.saveProficiencies = saves
        draft.spellcastingAbility = spellAbility
        draft.skillChoiceOptions = skillOptions
        draft.asiLevels = asiText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        draft.features = features.map { $0.toTrait() }
        library.upsert(draft)
        dismiss()
    }
}

// =====================================================================
//  SOUS-CLASSES
// =====================================================================

struct SubclassLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: Subclass?

    var body: some View {
        LibraryScaffold(
            title: "Sous-classes",
            subtitle: "Dupliquez ou créez une sous-classe maison.",
            query: $query,
            onNew: {
                let parent = library.classes.first?.id ?? ""
                editing = Subclass(id: "", name: "Nouvelle sous-classe",
                                   parentClassId: parent, features: [], isCustom: true)
            },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchSubclasses(query)) { sc in
                EntryRow(
                    name: sc.name,
                    detail: library.classes.first { $0.id == sc.parentClassId }?.name ?? "classe inconnue",
                    isCustom: sc.isCustom,
                    onDuplicate: { let c = library.duplicate(sc); library.upsert(c); editing = c },
                    onEdit: { editing = sc },
                    onDelete: { library.deleteSubclass(sc.id) }
                )
            }
        }
        .sheet(item: $editing) { sc in SubclassEditorSheet(subclass: sc) }
    }
}

struct SubclassEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Subclass
    @State private var features: [TraitRow]

    init(subclass: Subclass) {
        _draft = State(initialValue: subclass)
        _features = State(initialValue: subclass.features.map { TraitRow($0) })
    }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                    // Référence une classe existante : menu déroulant obligatoire.
                    Picker("Classe parente", selection: $draft.parentClassId) {
                        ForEach(library.classes) { c in Text(c.name).tag(c.id) }
                    }
                }
                Section("Capacités") {
                    TraitsEditor(rows: $features, withLevel: true)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "sousclasse") }
        draft.features = features.map { $0.toTrait() }
        library.upsert(draft)
        dismiss()
    }
}

// =====================================================================
//  DONS
// =====================================================================

struct FeatLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: Feat?

    var body: some View {
        LibraryScaffold(
            title: "Feats",
            subtitle: "Dupliquez ou créez un don maison. Affichage : nom + effet abrégé, sans effet mécanique.",
            query: $query,
            onNew: {
                editing = Feat(id: "", name: "Nouveau don", category: .general,
                               shortEffect: "", isCustom: true)
            },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchFeats(query)) { f in
                EntryRow(
                    name: f.name,
                    detail: f.category.rawValue,
                    isCustom: f.isCustom,
                    onDuplicate: { let c = library.duplicate(f); library.upsert(c); editing = c },
                    onEdit: { editing = f },
                    onDelete: { library.deleteFeat(f.id) }
                )
            }
        }
        .sheet(item: $editing) { f in FeatEditorSheet(feat: f) }
    }
}

struct FeatEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Feat
    @State private var grantsBonus: Bool

    init(feat: Feat) {
        _draft = State(initialValue: feat)
        _grantsBonus = State(initialValue: !feat.abilityBonusOptions.isEmpty)
    }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                    Picker("Catégorie", selection: $draft.category) {
                        ForEach(FeatCategory.allCases, id: \.self) { Text(featCategoryLabel($0)).tag($0) }
                    }
                }
                Section("Prérequis") {
                    TextField("ex. niveau 4+, Force 13 (vide si aucun)",
                              text: $draft.prerequisite, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Effet abrégé") {
                    TextField("Effet (résumé)", text: $draft.shortEffect, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Bonus de caractéristique") {
                    Toggle("Accorde un +1 à une caractéristique", isOn: $grantsBonus)
                    if grantsBonus {
                        ForEach(Ability.allCases, id: \.self) { a in
                            Toggle(a.rawValue, isOn: abilityOptionBinding(a))
                        }
                        Text("Une carac cochée = imposée · plusieurs = au choix · les six = choix libre.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: grantsBonus) { _, on in
            if on && draft.abilityBonusOptions.isEmpty { draft.abilityBonusOptions = Ability.allCases }
            if !on { draft.abilityBonusOptions = [] }
        }
    }

    /// Coche/décoche une carac éligible, en conservant l'ordre canonique.
    private func abilityOptionBinding(_ a: Ability) -> Binding<Bool> {
        Binding(
            get: { draft.abilityBonusOptions.contains(a) },
            set: { on in
                var s = Set(draft.abilityBonusOptions)
                if on { s.insert(a) } else { s.remove(a) }
                draft.abilityBonusOptions = Ability.allCases.filter { s.contains($0) }
            }
        )
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "don") }
        if !grantsBonus { draft.abilityBonusOptions = [] }
        library.upsert(draft)
        dismiss()
    }
}

// MARK: - Sorts maison

struct SpellLibrarySheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: Spell?

    var body: some View {
        LibraryScaffold(
            title: "Sorts",
            subtitle: "Créez un sort maison (nom, niveau, classes). Les sorts SRD restent intacts.",
            query: $query,
            onNew: {
                editing = Spell(id: "", name: "Nouveau sort", level: 0, classIds: [], isCustom: true)
            },
            onClose: { dismiss() }
        ) {
            ForEach(library.searchSpells(query)) { s in
                EntryRow(
                    name: s.name,
                    detail: spellLevelLabel(s.level),
                    isCustom: s.isCustom,
                    onDuplicate: { let c = library.duplicate(s); library.upsert(c); editing = c },
                    onEdit: { editing = s },
                    onDelete: { library.deleteSpell(s.id) }
                )
            }
        }
        .sheet(item: $editing) { s in SpellEditorSheet(spell: s) }
    }
}

struct SpellEditorSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Spell

    init(spell: Spell) { _draft = State(initialValue: spell) }

    var body: some View {
        EditorScaffold(title: draft.name, onCancel: { dismiss() }, onSave: save) {
            Form {
                Section("Identité") {
                    TextField("Nom", text: $draft.name)
                    Picker("Niveau", selection: $draft.level) {
                        ForEach(0...9, id: \.self) { lvl in
                            Text(spellLevelLabel(lvl)).tag(lvl)
                        }
                    }
                }
                Section("Classes qui peuvent l'apprendre") {
                    ForEach(library.classes) { cls in
                        Toggle(cls.name, isOn: classBinding(cls.id))
                    }
                    if library.classes.isEmpty {
                        Text("Aucune classe chargée.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Binding pour cocher/décocher une classe dans `classIds`.
    private func classBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { draft.classIds.contains(id) },
            set: { on in
                if on {
                    if !draft.classIds.contains(id) { draft.classIds.append(id) }
                } else {
                    draft.classIds.removeAll { $0 == id }
                }
            })
    }

    private func save() {
        if draft.id.isEmpty { draft.id = makeID(from: draft.name, prefix: "sort") }
        library.upsert(draft)
        dismiss()
    }
}

/// Libellé d'un niveau de sort (« Cantrip » pour 0, sinon « Niveau N »).
private func spellLevelLabel(_ level: Int) -> String {
    level == 0 ? "Cantrip" : "Niveau \(level)"
}

private func featCategoryLabel(_ c: FeatCategory) -> String {
    switch c {
    case .general:      return "General"
    case .origin:       return "Origin"
    case .fightingStyle: return "Fighting Style"
    case .epicBoon:     return "Epic Boon"
    }
}

// =====================================================================
//  IMPORT (un seul bouton, menu déroulant de type)
// =====================================================================

struct ImportContentSheet: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ContentLibrary.ImportKind = .species
    @State private var text = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Importer du contenu (JSON)").font(.headline)
            Text("Choisissez le type, puis collez un objet { … } ou un tableau [ … ]. Les entrées rejoignent la bibliothèque comme « maison ».")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Importer comme", selection: $kind) {
                ForEach(ContentLibrary.ImportKind.allCases) { k in Text(k.rawValue).tag(k) }
            }
            .pickerStyle(.menu)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))

            if let message {
                Text(message).font(.caption).foregroundStyle(isError ? .red : .green)
            }

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                Button("Importer") { runImport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 560, height: 500)
    }

    private func runImport() {
        switch library.importJSON(text, as: kind) {
        case .success(let n):
            isError = false
            message = "\(n) entrée·s importée·s comme « \(kind.rawValue) »."
            text = ""
        case .failure(let err):
            isError = true
            message = "JSON invalide : \(err.localizedDescription)"
        }
    }
}

// =====================================================================
//  Échafaudages réutilisables (bibliothèque & éditeur)
// =====================================================================

/// Cadre commun d'une fenêtre bibliothèque : titre, recherche, liste, boutons.
private struct LibraryScaffold<Rows: View>: View {
    let title: String
    let subtitle: String
    @Binding var query: String
    let onNew: () -> Void
    let onClose: () -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            TextField("Rechercher…", text: $query).textFieldStyle(.roundedBorder)

            List { rows() }
                .frame(minHeight: 340)

            HStack {
                Button(action: onNew) { Label("Nouveau", systemImage: "plus") }
                Spacer()
                Button("Fermer", action: onClose).buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 560, height: 560)
    }
}

/// Ligne d'entrée commune : nom, sous-titre, badge maison, actions.
private struct EntryRow: View {
    let name: String
    let detail: String
    let isCustom: Bool
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                    if isCustom { CustomBadge() }
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                .help("Dupliquer en version maison")
            if isCustom {
                Button(action: onEdit) { Image(systemName: "pencil") }.help("Éditer")
                // La suppression est différée d'un tick : sans cela, retirer la
                // ligne pendant que SwiftUI traite encore l'action du bouton
                // (qui appartient à cette même ligne) fige la List sur macOS.
                Button(role: .destructive) {
                    DispatchQueue.main.async(execute: onDelete)
                } label: { Image(systemName: "trash") }
                    .help("Supprimer")
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Cadre commun d'un éditeur sur feuille : titre + contenu + Annuler/Enregistrer.
private struct EditorScaffold<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            Text("Éditer « \(title) »").font(.headline)
            content()
            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                Button("Enregistrer", action: onSave).buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 620, height: 640)
    }
}
