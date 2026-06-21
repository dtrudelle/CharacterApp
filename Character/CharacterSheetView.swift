import SwiftUI

// =====================================================================
//  CharacterSheetView.swift
//  Rendu de la fiche (écran + cible de l'export PDF).
//  Lecture seule : prend un Character + ses références, calcule via SheetBuilder.
// =====================================================================

struct CharacterSheetView: View {
    let character: Character
    let references: SheetBuilder.References
    let sheet: ComputedSheet

    /// Dimensions d'une page (zone imprimable). Largeur fixe, hauteur minimale
    /// proportionnée (lettre) ; la page grandit si le contenu déborde.
    private let pageWidth: CGFloat = 600
    private let pageHeight: CGFloat = 776

    init(character: Character, references: SheetBuilder.References) {
        self.character = character
        self.references = references
        self.sheet = SheetBuilder.build(character, references)
    }

    /// Vrai si l'outil d'historique correspond à un outil de la liste (donc déjà
    /// présent dans `knownTools` : inutile de le répéter en texte).
    private var backgroundToolIsListed: Bool {
        let raw = references.background.toolProficiency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !raw.isEmpty else { return false }
        return references.tools.values.contains { $0.name.lowercased() == raw }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(pageViews().enumerated()), id: \.offset) { _, pg in pg }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Les pages prêtes (chrome + cadre fixe), pour l'affichage et l'export PDF.
    func pageViews() -> [AnyView] {
        [AnyView(page("page 1 / 2") { page1 }),
         AnyView(page("page 2 / 2") { page2 })]
    }

    /// Contenu « nu » de chaque page logique pour l'export : largeur fixe (= ratio
    /// Lettre), hauteur naturelle, fond blanc, mode clair forcé (PDF imprimable).
    /// PDFExport fenêtre ensuite ce contenu en pages physiques de hauteur fixe.
    func pdfLogicalPages() -> [AnyView] {
        [AnyView(pdfContent { page1 }),
         AnyView(pdfContent { page2 })]
    }

    private func pdfContent(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(28)
            .frame(width: pageWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.white)
            .environment(\.colorScheme, .light)
    }

    /// Dimensions d'une page physique imprimable (points), exposées à l'export.
    var printablePageHeight: CGFloat { pageHeight }
    var printablePageWidth: CGFloat { pageWidth }

    // MARK: - Page 1 (calculé)

    private var page1: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            abilitiesRow
            HStack(alignment: .top, spacing: 18) {
                savesColumn.frame(width: 200, alignment: .leading)
                skillsColumns
            }
            healthBand
            HStack(alignment: .top, spacing: 22) {
                combatBlock.frame(maxWidth: .infinity, alignment: .leading)
                spellsBlock.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(character.name).font(.title.weight(.medium))
                if !character.playerName.isEmpty {
                    Text("joueur · \(character.playerName)").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Text(references.species.name)
                Text("Background: \(references.background.name)")
                Text("\(references.characterClass.name) niveau \(character.level)")
                if let sub = references.subclass { Text(sub.name) }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var abilitiesRow: some View {
        HStack(spacing: 8) {
            ForEach(Ability.allCases, id: \.self) { a in
                VStack(spacing: 2) {
                    Text(a.rawValue).font(.caption2).foregroundStyle(.secondary)
                    Text("\(sheet.finalAbilities.score(a))").font(.title2.weight(.medium)).monospacedDigit()
                    Text(fmt(sheet.finalAbilities.modifier(a))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    private var savesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bonus de maîtrise").font(.caption).foregroundStyle(.secondary)
                Text(fmt(sheet.proficiencyBonus)).font(.headline).monospacedDigit()
            }
            .padding(.bottom, 10)
            sectionLabel("Jets de sauvegarde")
            ForEach(Ability.allCases, id: \.self) { a in
                HStack(spacing: 7) {
                    profMark(proficient: references.characterClass.saveProficiencies.contains(a), expertise: false)
                    Text(saveName(a)).font(.callout)
                    Spacer()
                    Text(fmt(sheet.saves[a] ?? 0)).font(.callout).monospacedDigit()
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var skillsColumns: some View {
        let half = (sheet.skills.count + 1) / 2
        let left = Array(sheet.skills.prefix(half))
        let right = Array(sheet.skills.dropFirst(half))
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Skill")
            HStack(alignment: .top, spacing: 18) {
                skillList(left)
                skillList(right)
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) { profMark(proficient: false, expertise: false); Text("non maîtrisée") }
                HStack(spacing: 4) { profMark(proficient: true, expertise: false); Text("maîtrisée") }
                HStack(spacing: 4) { profMark(proficient: true, expertise: true); Text("expertise") }
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func skillList(_ lines: [ComputedSheet.SkillLine]) -> some View {
        VStack(spacing: 0) {
            ForEach(lines, id: \.skill) { line in
                HStack(spacing: 7) {
                    profMark(proficient: line.proficient, expertise: line.expertise)
                    Text(line.skill.label).font(.callout)
                    Spacer()
                    Text(fmt(line.total)).font(.callout).monospacedDigit()
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Santé

    private var healthBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 20) {
                labelled("Points de vie") {
                    Text(character.hitPointsText.isEmpty ? "—" : character.hitPointsText)
                        .font(.title2.weight(.medium)).monospacedDigit()
                }
                Divider().frame(height: 36).overlay(Color.primary.opacity(0.35))
                labelled("Wounds · 10 + CON") {
                    Text("\(sheet.wounds)").font(.title2.weight(.medium)).monospacedDigit()
                }
                Divider().frame(height: 36).overlay(Color.primary.opacity(0.35))
                labelled("Dés de vie · \(sheet.hitDiceLabel)") {
                    dieBoxes(total: sheet.hitDiceTotal)
                }
            }
            Divider().overlay(Color.primary.opacity(0.35))
            HStack(spacing: 18) {
                HStack(spacing: 6) { Text("Blessé").font(.caption).foregroundStyle(.secondary); checkBox(filled: false) }
                Divider().frame(height: 18).overlay(Color.primary.opacity(0.35))
                Text("Jets contre la mort").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) { Text("Réussites").font(.caption2).foregroundStyle(.secondary); boxes(3, filled: 0) }
                HStack(spacing: 5) { Text("Échecs").font(.caption2).foregroundStyle(.secondary); boxes(3, filled: 0) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.35)))
    }

    // MARK: Combat & sorts

    private var combatBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Combat")
            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    metric("CA", character.armorClassText)
                    metric("Initiative", character.initiativeText)
                }
                GridRow {
                    metric("Jet FOR", fmt(sheet.toHitSTR))
                    metric("Jet DEX", fmt(sheet.toHitDEX))
                }
                GridRow {
                    metric("Dégâts FOR", fmt(sheet.damageSTR))
                    metric("Dégâts DEX", fmt(sheet.damageDEX))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.35)))
        }
    }

    private var spellsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Sorts")
            if let dc = sheet.spellSaveDC {
                HStack(spacing: 8) {
                    metric("DC de save", "\(dc)")
                    metric("Attaque de sort", fmt(sheet.spellAttackBonus ?? 0))
                }
                HStack(spacing: 8) {
                    if let c = sheet.cantripsKnown { metric("Cantrips", "\(c)") }
                    if let p = sheet.preparedSpells { metric("Sorts préparés", "\(p)") }
                }
                slotTable(sheet.spellSlots)
            } else {
                Text("Non-lanceur").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func slotTable(_ slots: [ComputedSheet.SlotLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Niveau").font(.caption2).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    ForEach(slots, id: \.spellLevel) { s in slotCell("\(s.spellLevel)", strong: false) }
                }
                GridRow {
                    ForEach(slots, id: \.spellLevel) { s in slotCell("\(s.count)", strong: true) }
                }
            }
        }
    }

    // MARK: - Page 2 (descriptif)

    private var page2: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Capacités & traits")
                ForEach(Array(sheet.featureGroups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.source).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(group.features.enumerated()), id: \.offset) { _, feat in
                                featureRow(name: feat.name,
                                          tag: feat.level.map { "niv. \($0)" },
                                          description: feat.description)
                            }
                        }
                    }
                }
            }

            if !sheet.feats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Feats")
                    ForEach(sheet.feats) { feat in
                        featureRow(name: feat.name, tag: feat.category.rawValue, description: feat.shortEffect)
                    }
                }
            }

            if !sheet.knownSpells.isEmpty || !character.spellListText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Sorts connus")
                    ForEach(sheet.knownSpells) { group in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(group.names.joined(separator: ", "))
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !character.spellListText.isEmpty {
                        Text(character.spellListText)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !sheet.knownTools.isEmpty || !references.background.toolProficiency.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Outils — maîtrises")
                    // Texte libre seulement si l'outil d'historique ne correspond
                    // à aucun outil de la liste (sinon il figure déjà dans knownTools).
                    if !references.background.toolProficiency.isEmpty, !backgroundToolIsListed {
                        Text("Historique : \(references.background.toolProficiency)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !sheet.knownTools.isEmpty {
                        Text(sheet.knownTools.joined(separator: ", "))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Équipement")
                // Sélection des catalogues (résolue), groupée par catégorie.
                ForEach(sheet.ownedEquipment) { group in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.category).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(group.names.joined(separator: ", "))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Texte libre : objets hors catalogue (toujours conservé).
                if !character.equipmentText.isEmpty {
                    Text(character.equipmentText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if sheet.ownedEquipment.isEmpty {
                    Text("—").font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Monnaie")
                HStack(spacing: 8) {
                    metric("Auréon", "\(character.currency.aureon)")
                    metric("Solari", "\(character.currency.solari)")
                    metric("Scaille", "\(character.currency.scaille)")
                }
            }

            textBlock("Notes", character.notesText)
        }
    }

    // MARK: - Briques réutilisables

    private func page(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(22)
            .frame(minWidth: pageWidth, maxWidth: pageWidth, minHeight: pageHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.35)))
            .overlay(alignment: .topTrailing) {
                Text(label).font(.caption2).foregroundStyle(.tertiary).padding(12)
            }
    }

    private func sectionLabel(_ t: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption.weight(.bold)).foregroundStyle(.primary)
            Divider().overlay(Color.primary.opacity(0.35))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).font(.title3.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.35)))
    }

    private func slotCell(_ value: String, strong: Bool) -> some View {
        Text(value)
            .font(strong ? .callout.weight(.medium) : .caption)
            .monospacedDigit()
            .frame(width: 24, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.35)))
    }

    private func featureRow(name: String, tag: String?, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(name).font(.callout.weight(.medium))
                if let tag, !tag.isEmpty {
                    Text("· \(tag)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textBlock(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(content.isEmpty ? "—" : content)
                .font(.callout)
                .foregroundStyle(content.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labelled(_ title: String, @ViewBuilder _ value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            value()
        }
    }

    @ViewBuilder
    private func profMark(proficient: Bool, expertise: Bool) -> some View {
        if expertise {
            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.primary)
        } else if proficient {
            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.primary)
        } else {
            Image(systemName: "circle").font(.system(size: 7)).foregroundStyle(.secondary)
        }
    }

    private func checkBox(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(filled ? Color.primary : Color.clear)
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary, lineWidth: 1))
    }

    private func boxes(_ count: Int, filled: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in checkBox(filled: i < filled) }
        }
    }

    /// Une case vide par dé de vie (fiche papier : cochée au crayon), par rangées de 10.
    private func dieBoxes(total: Int) -> some View {
        let rows = stride(from: 0, to: max(total, 0), by: 10).map { Array($0..<min($0 + 10, total)) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { _ in checkBox(filled: false) }
                }
            }
        }
    }

    private func fmt(_ n: Int) -> String { n >= 0 ? "+\(n)" : "−\(abs(n))" }

    private func saveName(_ a: Ability) -> String {
        switch a {
        case .STR: return "Strength"
        case .DEX: return "Dextérité"
        case .CON: return "Constitution"
        case .INT: return "Intelligence"
        case .WIS: return "Wisdom"
        case .CHA: return "Charisme"
        }
    }
}

#Preview {
    CharacterSheetView(character: SheetBuilder.exampleCharacter,
                       references: SheetBuilder.exampleReferences)
        .frame(width: 680, height: 920)
}
