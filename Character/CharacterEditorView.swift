import SwiftUI

// =====================================================================
//  CharacterEditorView.swift
//  Saisie d'un personnage (formulaire) + aperçu live de la fiche.
//  Produit un `Character` valide à partir des menus contraints par la classe.
// =====================================================================

// MARK: - États d'édition pour la répartition des bonus

/// Motif du bonus d'historique (placement libre, motif fixe).
enum ASIPatternCreation: String, CaseIterable {
    case twoOne = "+2 / +1"
    case oneOneOne = "+1 / +1 / +1"
}

/// Motif d'une amélioration de niveau.
enum ASIPatternLevel: String, CaseIterable {
    case two = "+2"
    case oneOne = "+1 / +1"
}

/// Répartition du bonus d'historique.
struct BackgroundASI {
    var pattern: ASIPatternCreation = .twoOne
    var a1: Ability = .STR
    var a2: Ability = .DEX
    var a3: Ability = .CON

    func allocations() -> [Ability: Int] {
        switch pattern {
        case .twoOne:    return mergeSum([(a1, 2), (a2, 1)])
        case .oneOneOne: return mergeSum([(a1, 1), (a2, 1), (a3, 1)])
        }
    }
}

/// Choix fait à un niveau d'amélioration : rien, une augmentation, ou un don.
struct LevelASIState {
    enum Kind: String, CaseIterable {
        case none = "Aucun"
        case increase = "Caractéristique"
        case feat = "Feat"
    }
    var kind: Kind = .none
    var pattern: ASIPatternLevel = .two
    var a1: Ability = .STR
    var a2: Ability = .DEX
    var featId: String = ""

    func allocations() -> [Ability: Int] {
        switch pattern {
        case .two:    return mergeSum([(a1, 2)])
        case .oneOne: return mergeSum([(a1, 1), (a2, 1)])
        }
    }
}

private func mergeSum(_ pairs: [(Ability, Int)]) -> [Ability: Int] {
    var d: [Ability: Int] = [:]
    for (a, v) in pairs { d[a, default: 0] += v }
    return d
}

/// Entrées « bonus » (hors progression normale). Identité stable (UUID) pour
/// éviter les collisions de ForEach avec les autres listes de la même section.
struct BonusSkillEntry: Identifiable { let id = UUID(); var skill: Skill }
struct BonusFeatEntry: Identifiable { let id = UUID(); var featId: String }

// MARK: - Vue

struct CharacterEditorView: View {
    let library: ContentLibrary
    let onChange: (Character) -> Void

    @State private var character: Character
    @State private var bgASI: BackgroundASI
    @State private var levelStates: [Int: LevelASIState]
    @State private var chosenSkills: [Skill?]
    @State private var bonusSkills: [BonusSkillEntry]
    @State private var expertiseSet: Set<Skill>
    @State private var bonusFeatIds: [BonusFeatEntry]

    // État d'UI pour la sélection des sorts (non persisté).
    @State private var spellSearch = ""
    @State private var expandedLevels: Set<Int> = []

    init(character: Character, library: ContentLibrary, onChange: @escaping (Character) -> Void) {
        self.library = library
        self.onChange = onChange
        _character = State(initialValue: character)

        // Reconstruit l'état des menus à partir du personnage chargé.
        var bg = BackgroundASI()
        var levels: [Int: LevelASIState] = [:]
        for inc in character.abilityIncreases {
            if inc.source.hasPrefix("Background") {
                bg = Self.backgroundASI(from: inc.allocations)
            } else if let lvl = Self.level(from: inc.source) {
                levels[lvl] = Self.levelIncrease(from: inc.allocations)
            }
        }
        for fc in character.featChoices {
            if let lvl = Self.level(from: fc.source) {
                var st = levels[lvl] ?? LevelASIState()
                st.kind = .feat
                st.featId = fc.featId
                levels[lvl] = st
            }
        }
        _bgASI = State(initialValue: bg)
        _levelStates = State(initialValue: levels)
        _bonusFeatIds = State(initialValue: character.featChoices
            .filter { Self.level(from: $0.source) == nil }
            .map { BonusFeatEntry(featId: $0.featId) })

        let cls = library.classes.first { $0.id == character.classId } ?? library.classes.first
        let count = cls?.skillChoiceCount ?? 0
        var slots = Array<Skill?>(repeating: nil, count: count)
        for (i, sk) in character.chosenClassSkills.prefix(count).enumerated() { slots[i] = sk }
        _chosenSkills = State(initialValue: slots)
        _bonusSkills = State(initialValue: Array(character.chosenClassSkills.dropFirst(count))
            .map { BonusSkillEntry(skill: $0) })
        _expertiseSet = State(initialValue: Set(character.expertise))
    }

    var body: some View {
        HSplitView {
            Form {
                identitySection
                abilitiesSection
                increasesSection
                skillsSection
                healthCombatSection
                spellsSelectionSection
                toolsSelectionSection
                textSection
            }
            .formStyle(.grouped)
            .frame(minWidth: 380, idealWidth: 440)

            preview.frame(minWidth: 640)
        }
        .onAppear {
            syncBackgroundTool()
        }
        .onChange(of: character.classId) { _, newId in
            let cls = library.classes.first { $0.id == newId }
                ?? library.classes.first
                ?? CharacterClass.empty
            chosenSkills = Array(repeating: nil, count: cls.skillChoiceCount)
            character.subclassId = nil
            levelStates = [:]
            expertiseSet = []
            character.knownSpellIds = []
            spellSearch = ""
            expandedLevels = []
        }
        .onChange(of: character.backgroundId) { oldId, newId in
            updateBackgroundTool(from: oldId, to: newId)
        }
        .onChange(of: character.level) { _, lvl in
            levelStates = levelStates.filter { $0.key <= lvl }
        }
        .onChange(of: liveCharacter) { _, updated in
            onChange(updated)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportPDF()
                } label: {
                    Label("Exporter en PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func exportPDF() {
        guard let refs = library.references(for: liveCharacter) else { return }
        PDFExport.exportWithSavePanel(character: liveCharacter, references: refs)
    }

    // MARK: Aperçu

    private var preview: some View {
        Group {
            if let refs = library.references(for: liveCharacter) {
                CharacterSheetView(character: liveCharacter, references: refs)
            } else {
                Text("Sélection incomplète").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sections du formulaire

    private var identitySection: some View {
        Section("Identité") {
            TextField("Nom", text: $character.name)
            TextField("Joueur", text: $character.playerName)
            Picker("Espèce", selection: $character.speciesId) {
                ForEach(library.species) { Text($0.name).tag($0.id) }
            }
            Picker("Background", selection: $character.backgroundId) {
                ForEach(library.backgrounds) { Text($0.name).tag($0.id) }
            }
            Picker("Classe", selection: $character.classId) {
                ForEach(library.classes) { Text($0.name).tag($0.id) }
            }
            Picker("Sous-classe", selection: subclassBinding) {
                Text("Aucune").tag("")
                ForEach(subclasses(of: character.classId)) { Text($0.name).tag($0.id) }
            }
            Stepper("Level: \(character.level)", value: $character.level, in: 1...20)
        }
    }

    private var abilitiesSection: some View {
        Section("Caractéristiques (base)") {
            abilityStepper("Force", $character.baseAbilities.STR)
            abilityStepper("Dextérité", $character.baseAbilities.DEX)
            abilityStepper("Constitution", $character.baseAbilities.CON)
            abilityStepper("Intelligence", $character.baseAbilities.INT)
            abilityStepper("Sagesse", $character.baseAbilities.WIS)
            abilityStepper("Charisme", $character.baseAbilities.CHA)
            Text("Scores finaux (avec bonus) calculés sur la fiche.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var increasesSection: some View {
        Section("Bonus de caractéristique") {
            LabeledContent("Background") { EmptyView() }
            backgroundASIRow
            ForEach(asiLevelsUpTo, id: \.self) { lvl in
                Divider()
                levelASIRow(lvl)
            }
            Divider()
            bonusFeatsBlock
        }
    }

    private var skillsSection: some View {
        Section("Compétences") {
            Text("Background: \(currentBackground.skillProficiencies.map(\.label).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<currentClass.skillChoiceCount, id: \.self) { i in
                Picker("Compétence \(i + 1)", selection: skillSlotBinding(i)) {
                    Text("—").tag(Optional<Skill>.none)
                    ForEach(eligibleSkills(for: i), id: \.self) { sk in
                        Text(sk.label).tag(Optional(sk))
                    }
                }
            }
            ForEach($bonusSkills) { $entry in
                HStack {
                    Picker("Compétence bonus", selection: $entry.skill) {
                        ForEach(Skill.allCases, id: \.self) { sk in Text(sk.label).tag(sk) }
                    }
                    Button(role: .destructive) {
                        bonusSkills.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let pick = Skill.allCases.first { !proficientSkills.contains($0) } ?? Skill.allCases[0]
                bonusSkills.append(BonusSkillEntry(skill: pick))
            } label: {
                Label("Ajouter une compétence (don / règle maison)", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            if !proficientSkills.isEmpty {
                DisclosureGroup("Expertise") {
                    ForEach(Array(proficientSkills).sorted { $0.label < $1.label }, id: \.self) { sk in
                        Toggle(sk.label, isOn: expertiseBinding(sk))
                    }
                }
            }
        }
    }

    private var healthCombatSection: some View {
        Section("Santé & combat (saisie)") {
            TextField("Points de vie (ex. 38 / 38)", text: $character.hitPointsText)
            TextField("Classe d'armure (ex. 18 …)", text: $character.armorClassText)
            TextField("Initiative (ex. +2)", text: $character.initiativeText)
        }
    }

    private var spellsSelectionSection: some View {
        Section("Sorts") {
            if isCaster {
                TextField("Rechercher un sort", text: $spellSearch)
                    .textFieldStyle(.roundedBorder)
                ForEach(shownSpellLevels, id: \.self) { lvl in
                    DisclosureGroup(isExpanded: levelExpanded(lvl)) {
                        ForEach(shownSpells(at: lvl)) { spell in
                            Toggle(spell.name, isOn: spellBinding(spell.id))
                        }
                    } label: {
                        HStack {
                            Text(levelTitle(lvl))
                            Spacer()
                            Text("\(selectedCount(at: lvl)) choisi(s)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if shownSpellLevels.isEmpty {
                    Text("Aucun sort ne correspond.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Classe non-lanceuse.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var toolsSelectionSection: some View {
        Section("Outils") {
            // Texte libre seulement si l'outil d'historique ne correspond à aucun
            // outil de la liste (sinon il est coché ci-dessous, pas besoin de doublon).
            if !currentBackground.toolProficiency.isEmpty, backgroundToolMatch == nil {
                Text("Historique : \(currentBackground.toolProficiency)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(chosenTools) { tool in
                HStack {
                    Text(tool.name)
                    if tool.id == backgroundToolMatch?.id {
                        Text("(historique)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        character.chosenToolIds.removeAll { $0 == tool.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            if availableTools.isEmpty {
                Text("Tous les outils sont déjà ajoutés.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(availableTools) { tool in
                        Button(tool.name) {
                            character.chosenToolIds.append(tool.id)
                        }
                    }
                } label: {
                    Label("Ajouter un outil", systemImage: "plus.circle")
                }
            }
        }
    }

    private var textSection: some View {
        Section("Équipement, monnaie, notes") {
            LabeledContent("Sorts maison (texte libre)") { EmptyView() }
            TextEditor(text: $character.spellListText).frame(minHeight: 50)
            LabeledContent("Équipement") { EmptyView() }
            TextEditor(text: $character.equipmentText).frame(minHeight: 60)
            TextField("Auréon", value: $character.currency.aureon, format: .number)
            TextField("Solari", value: $character.currency.solari, format: .number)
            TextField("Scaille", value: $character.currency.scaille, format: .number)
            LabeledContent("Notes") { EmptyView() }
            TextEditor(text: $character.notesText).frame(minHeight: 50)
        }
    }

    // MARK: Lignes complexes

    private var backgroundASIRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Motif", selection: $bgASI.pattern) {
                ForEach(ASIPatternCreation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack(spacing: 10) {
                abilityPicker($bgASI.a1); Text(bgASI.pattern == .twoOne ? "+2" : "+1").foregroundStyle(.secondary)
                abilityPicker($bgASI.a2); Text("+1").foregroundStyle(.secondary)
                if bgASI.pattern == .oneOneOne {
                    abilityPicker($bgASI.a3); Text("+1").foregroundStyle(.secondary)
                }
            }
            Text("Recommandé : \(currentBackground.abilityOptions.map(\.rawValue).joined(separator: ", ")) — placement libre.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func levelASIRow(_ lvl: Int) -> some View {
        let b = levelBinding(lvl)
        return VStack(alignment: .leading, spacing: 6) {
            Picker("Level \(lvl)", selection: b.kind) {
                ForEach(LevelASIState.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            switch b.wrappedValue.kind {
            case .none:
                EmptyView()
            case .increase:
                HStack(spacing: 10) {
                    Picker("", selection: b.pattern) {
                        ForEach(ASIPatternLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    abilityPicker(b.a1)
                    if b.wrappedValue.pattern == .oneOne { abilityPicker(b.a2) }
                }
            case .feat:
                Picker("Feat", selection: b.featId) {
                    Text("—").tag("")
                    ForEach(library.feats) { Text($0.name).tag($0.id) }
                }
            }
        }
    }

    private var bonusFeatsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Additional Feats").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ForEach($bonusFeatIds) { $entry in
                HStack {
                    Picker("", selection: $entry.featId) {
                        Text("—").tag("")
                        ForEach(library.feats) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    Button(role: .destructive) {
                        bonusFeatIds.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                bonusFeatIds.append(BonusFeatEntry(featId: ""))
            } label: {
                Label("Ajouter un don (acquis hors progression normale)", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Briques

    private func abilityStepper(_ name: String, _ value: Binding<Int>) -> some View {
        Stepper("\(name) : \(value.wrappedValue)", value: value, in: 1...30)
    }

    private func abilityPicker(_ sel: Binding<Ability>) -> some View {
        Picker("", selection: sel) {
            ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden().fixedSize()
    }

    // MARK: Bindings dérivés

    private var subclassBinding: Binding<String> {
        Binding(get: { character.subclassId ?? "" },
                set: { character.subclassId = $0.isEmpty ? nil : $0 })
    }

    private func skillSlotBinding(_ i: Int) -> Binding<Skill?> {
        Binding(get: { i < chosenSkills.count ? chosenSkills[i] : nil },
                set: { if i < chosenSkills.count { chosenSkills[i] = $0 } })
    }

    private func expertiseBinding(_ sk: Skill) -> Binding<Bool> {
        Binding(get: { expertiseSet.contains(sk) },
                set: { on in if on { expertiseSet.insert(sk) } else { expertiseSet.remove(sk) } })
    }

    private func levelBinding(_ lvl: Int) -> Binding<LevelASIState> {
        Binding(get: { levelStates[lvl] ?? LevelASIState() },
                set: { levelStates[lvl] = $0 })
    }

    // MARK: Reconstruction (personnage chargé -> état des menus)

    private static func level(from source: String) -> Int? {
        guard let r = source.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(source[r])
    }

    private static func backgroundASI(from alloc: [Ability: Int]) -> BackgroundASI {
        var bg = BackgroundASI()
        if let two = alloc.first(where: { $0.value >= 2 })?.key {
            bg.pattern = .twoOne
            bg.a1 = two
            bg.a2 = alloc.first(where: { $0.value == 1 })?.key ?? bg.a2
        } else {
            bg.pattern = .oneOneOne
            let keys = Array(alloc.keys)
            if keys.indices.contains(0) { bg.a1 = keys[0] }
            if keys.indices.contains(1) { bg.a2 = keys[1] }
            if keys.indices.contains(2) { bg.a3 = keys[2] }
        }
        return bg
    }

    private static func levelIncrease(from alloc: [Ability: Int]) -> LevelASIState {
        var st = LevelASIState()
        st.kind = .increase
        if let two = alloc.first(where: { $0.value >= 2 })?.key {
            st.pattern = .two
            st.a1 = two
        } else {
            st.pattern = .oneOne
            let keys = Array(alloc.keys)
            if keys.indices.contains(0) { st.a1 = keys[0] }
            if keys.indices.contains(1) { st.a2 = keys[1] }
        }
        return st
    }

    // MARK: Dérivés

    private var currentClass: CharacterClass {
        library.classes.first { $0.id == character.classId }
            ?? library.classes.first
            ?? CharacterClass.empty
    }

    private var currentBackground: Background {
        library.backgrounds.first { $0.id == character.backgroundId }
            ?? library.backgrounds.first
            ?? Background.empty
    }

    private func subclasses(of classId: String) -> [Subclass] {
        library.subclasses.filter { $0.parentClassId == classId }
    }

    private var asiLevelsUpTo: [Int] {
        currentClass.asiLevels.filter { $0 <= character.level }.sorted()
    }

    private var proficientSkills: Set<Skill> {
        Set(currentBackground.skillProficiencies + chosenSkills.compactMap { $0 } + bonusSkills.map(\.skill))
    }

    // MARK: Sorts

    private var isCaster: Bool { currentClass.spellcastingAbility != nil }

    private var filteredClassSpells: [Spell] {
        let q = spellSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return library.spells.filter { spell in
            spell.classIds.contains(character.classId)
                && (q.isEmpty || spell.name.lowercased().contains(q))
        }
    }

    private var shownSpellLevels: [Int] {
        Array(Set(filteredClassSpells.map(\.level))).sorted()
    }

    private func shownSpells(at level: Int) -> [Spell] {
        filteredClassSpells.filter { $0.level == level }
    }

    /// Sorts cochés à ce niveau (indépendant de la recherche).
    private func selectedCount(at level: Int) -> Int {
        library.spells.filter {
            $0.level == level && $0.classIds.contains(character.classId)
                && character.knownSpellIds.contains($0.id)
        }.count
    }

    private func levelTitle(_ level: Int) -> String {
        level == 0 ? "Cantrips" : "Level \(level)"
    }

    private func spellBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { character.knownSpellIds.contains(id) },
            set: { on in
                if on {
                    if !character.knownSpellIds.contains(id) { character.knownSpellIds.append(id) }
                } else {
                    character.knownSpellIds.removeAll { $0 == id }
                }
            })
    }

    /// Replié par défaut ; déplié d'office quand une recherche est active.
    private func levelExpanded(_ level: Int) -> Binding<Bool> {
        Binding(
            get: { !spellSearch.isEmpty || expandedLevels.contains(level) },
            set: { open in
                if open { expandedLevels.insert(level) } else { expandedLevels.remove(level) }
            })
    }

    /// Options de compétence d'un slot : liste de la classe, moins les compétences
    /// d'historique et celles déjà choisies dans les autres slots.
    private func eligibleSkills(for slot: Int) -> [Skill] {
        let takenElsewhere = chosenSkills.enumerated()
            .filter { $0.offset != slot }
            .compactMap { $0.element }
        let exclude = Set(currentBackground.skillProficiencies + takenElsewhere)
        return currentClass.skillChoiceOptions.filter { !exclude.contains($0) }
    }

    private var assembledIncreases: [AbilityIncrease] {
        var result = [AbilityIncrease(source: "Background", allocations: bgASI.allocations())]
        for lvl in asiLevelsUpTo {
            let st = levelStates[lvl] ?? LevelASIState()
            if st.kind == .increase {
                result.append(AbilityIncrease(source: "Level \(lvl)", allocations: st.allocations()))
            }
        }
        return result
    }

    private var assembledFeatChoices: [FeatChoice] {
        let levelFeats = asiLevelsUpTo.compactMap { lvl -> FeatChoice? in
            let st = levelStates[lvl] ?? LevelASIState()
            guard st.kind == .feat, !st.featId.isEmpty else { return nil }
            return FeatChoice(source: "Level \(lvl)", featId: st.featId)
        }
        let bonus = bonusFeatIds.map(\.featId).filter { !$0.isEmpty }
            .map { FeatChoice(source: "Bonus", featId: $0) }
        return levelFeats + bonus
    }

    /// Le personnage tel qu'affiché : `character` enrichi des choix d'édition.
    // MARK: Outils

    /// L'outil de l'historique courant, résolu vers un Tool de la liste si le texte
    /// correspond à un nom connu (sinon nil → reste affiché en texte libre).
    private var backgroundToolMatch: Tool? {
        toolMatch(forBackgroundId: character.backgroundId)
    }

    /// Résout l'outil (de la liste) correspondant au `toolProficiency` d'un
    /// historique donné par son id. nil si le texte ne correspond à aucun outil.
    private func toolMatch(forBackgroundId id: String) -> Tool? {
        guard let bg = library.backgrounds.first(where: { $0.id == id }) else { return nil }
        let raw = bg.toolProficiency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !raw.isEmpty else { return nil }
        return library.tools.first { $0.name.lowercased() == raw }
    }

    /// Ajoute l'outil de l'historique courant aux outils choisis (comme s'il était
    /// coché). Idempotent ; utilisé au démarrage.
    private func syncBackgroundTool() {
        guard let tool = backgroundToolMatch else { return }
        if !character.chosenToolIds.contains(tool.id) {
            character.chosenToolIds.append(tool.id)
        }
    }

    /// Au changement d'historique : retire l'outil de l'ancien (s'il avait été
    /// ajouté automatiquement) et ajoute celui du nouveau.
    private func updateBackgroundTool(from oldId: String, to newId: String) {
        if let old = toolMatch(forBackgroundId: oldId) {
            character.chosenToolIds.removeAll { $0 == old.id }
        }
        if let new = toolMatch(forBackgroundId: newId),
           !character.chosenToolIds.contains(new.id) {
            character.chosenToolIds.append(new.id)
        }
    }

    /// Outils choisis, résolus dans l'ordre d'ajout.
    private var chosenTools: [Tool] {
        character.chosenToolIds.compactMap { id in library.tools.first { $0.id == id } }
    }

    /// Outils encore disponibles (non choisis), triés par nom.
    private var availableTools: [Tool] {
        let chosen = Set(character.chosenToolIds)
        return library.tools
            .filter { !chosen.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    private var liveCharacter: Character {
        var c = character
        c.abilityIncreases = assembledIncreases
        c.featChoices = assembledFeatChoices
        c.chosenClassSkills = chosenSkills.compactMap { $0 } + bonusSkills.map(\.skill)
        c.expertise = expertiseSet.intersection(proficientSkills).sorted { $0.rawValue < $1.rawValue }
        c.knownSpellIds = character.knownSpellIds.sorted()
        return c
    }
}

#Preview {
    let library = ContentLibrary.preview
    CharacterEditorView(character: CharacterStore.newCharacter(library: library),
                        library: library, onChange: { _ in })
        .frame(width: 1100, height: 820)
}
