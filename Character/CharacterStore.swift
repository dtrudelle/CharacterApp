import Foundation
import Observation

// =====================================================================
//  CharacterStore.swift
//  Persistance des personnages : tableau observable + lecture/écriture JSON
//  dans Application Support/CharacterApp/characters.json.
// =====================================================================

@Observable
final class CharacterStore {
    private(set) var characters: [Character] = []
    var selectedID: Character.ID?

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CharacterApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("characters.json")
        print("📁 CharacterApp lit/écrit ses données ici :\n   \(dir.path)")
        load()
    }

    // MARK: Disque

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Character].self, from: data) else { return }
        characters = list
        selectedID = characters.first?.id
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(characters) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: CRUD

    var selected: Character? { characters.first { $0.id == selectedID } }

    func add(_ character: Character) {
        characters.append(character)
        // Différer la sélection d'un tick pour laisser SwiftUI propager
        // l'insertion dans `characters` avant que `detail` l'évalue.
        Task { @MainActor in self.selectedID = character.id }
        save()
    }

    /// Met à jour si différent (évite les écritures inutiles à chaque frappe inchangée).
    func update(_ character: Character) {
        guard let i = characters.firstIndex(where: { $0.id == character.id }) else { return }
        guard characters[i] != character else { return }
        characters[i] = character
        save()
    }

    func delete(_ id: Character.ID) {
        characters.removeAll { $0.id == id }
        if selectedID == id { selectedID = characters.first?.id }
        save()
    }

    func duplicate(_ id: Character.ID) {
        guard let original = characters.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID().uuidString
        copy.name = original.name + " (copie)"
        add(copy)
    }

    // MARK: Fabrique

    static func newCharacter(library: ContentLibrary) -> Character {
        Character(
            name: "Nouveau personnage",
            speciesId: library.species.first?.id ?? "",
            backgroundId: library.backgrounds.first?.id ?? "",
            classId: library.classes.first?.id ?? "",
            level: 1,
            baseAbilities: AbilityScores(STR: 10, DEX: 10, CON: 10, INT: 10, WIS: 10, CHA: 10)
        )
    }
}
