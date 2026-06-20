import SwiftUI

// =====================================================================
//  CharacterApp.swift
//  Point d'entrée + vue racine maître-détail : liste des personnages
//  sauvegardés (CharacterStore) à gauche, éditeur du personnage sélectionné
//  à droite. La bibliothèque de contenu (SRD + maison) est partagée via
//  l'environnement pour que les fenêtres « Bibliothèque » la modifient.
// =====================================================================

@main
struct CharacterApp: App {
    @State private var store = CharacterStore()
    @State private var library = ContentLibrary.loadBundled()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, library: library)
                .environment(library)
                .frame(minWidth: 1100, minHeight: 720)
        }
    }
}

struct RootView: View {
    @Bindable var store: CharacterStore
    @Bindable var library: ContentLibrary

    /// Pilote l'ouverture des fenêtres de bibliothèque depuis le menu.
    @State private var libraryRoute: LibraryRoute?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $libraryRoute) { route in
            LibraryRouter(route: route)
                .environment(library)
        }
    }

    // MARK: Liste

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedID) {
                ForEach(store.characters) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name.isEmpty ? "Sans nom" : c.name)
                        Text(subtitle(c)).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(c.id)
                }
            }
            Divider()
            sidebarButtons
        }
        .navigationTitle("Personnages")
        .frame(minWidth: 220)
    }

    /// Boutons toujours visibles (dans le corps de la vue, pas dans la toolbar
    /// système qui les repliait sous le chevron de débordement). Même approche
    /// que la barre de boutons de l'app de combat.
    private var sidebarButtons: some View {
        HStack(spacing: 6) {
            Button {
                store.add(CharacterStore.newCharacter(library: library))
            } label: { Label("Nouveau", systemImage: "plus") }
                .help("Nouveau personnage")

            Button {
                if let id = store.selectedID { store.duplicate(id) }
            } label: { Label("Dupliquer", systemImage: "plus.square.on.square").labelStyle(.iconOnly) }
                .help("Dupliquer le personnage")
                .disabled(store.selectedID == nil)

            Button(role: .destructive) {
                if let id = store.selectedID { store.delete(id) }
            } label: { Label("Supprimer", systemImage: "trash").labelStyle(.iconOnly) }
                .help("Supprimer le personnage")
                .disabled(store.selectedID == nil)

            Spacer()

            // Bibliothèque → sous-menu des cinq types + import.
            Menu {
                Button { libraryRoute = .species }     label: { Label("Espèces", systemImage: "person.3") }
                Button { libraryRoute = .backgrounds } label: { Label("Historiques", systemImage: "scroll") }
                Button { libraryRoute = .classes }     label: { Label("Classes", systemImage: "shield") }
                Button { libraryRoute = .subclasses }  label: { Label("Sous-classes", systemImage: "shield.lefthalf.filled") }
                Button { libraryRoute = .feats }       label: { Label("Feats", systemImage: "star") }
                Divider()
                Button { libraryRoute = .importer }    label: { Label("Importer…", systemImage: "square.and.arrow.down") }
            } label: {
                Label("Bibliothèque", systemImage: "books.vertical")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Bibliothèque de contenu")
        }
        .controlSize(.small)
        .padding(8)
    }

    // MARK: Détail

    @ViewBuilder
    private var detail: some View {
        if let selected = store.selected {
            CharacterEditorView(character: selected, library: library) { updated in
                store.update(updated)
            }
            .id(selected.id)
        } else {
            ContentUnavailableView("Aucun personnage",
                                   systemImage: "person.crop.rectangle",
                                   description: Text("Crée ou sélectionne un personnage."))
        }
    }

    private func subtitle(_ c: Character) -> String {
        let cls = library.classes.first { $0.id == c.classId }?.name ?? "—"
        return "\(cls) · niveau \(c.level)"
    }
}

// MARK: - Routage des fenêtres de bibliothèque

enum LibraryRoute: String, Identifiable {
    case species, backgrounds, classes, subclasses, feats, importer
    var id: String { rawValue }
}

/// Aiguille vers la bonne fenêtre selon l'entrée de menu choisie.
struct LibraryRouter: View {
    let route: LibraryRoute

    var body: some View {
        switch route {
        case .species:     SpeciesLibrarySheet()
        case .backgrounds: BackgroundLibrarySheet()
        case .classes:     ClassLibrarySheet()
        case .subclasses:  SubclassLibrarySheet()
        case .feats:       FeatLibrarySheet()
        case .importer:    ImportContentSheet()
        }
    }
}

