// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

@MainActor
final class CustomRulesService: ObservableObject {
    @Published var rules: [CustomRule] = []

    private let configDir: URL
    private let rulesFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".drivesyncai", isDirectory: true)
        rulesFile = configDir.appendingPathComponent("custom_rules.json")
        loadRules()
    }

    func loadRules() {
        guard let data = try? Data(contentsOf: rulesFile),
              let decoded = try? JSONDecoder().decode([CustomRule].self, from: data) else {
            if rules.isEmpty {
                rules = Self.defaultRules
                saveRules()
            }
            return
        }
        rules = decoded
    }

    func saveRules() {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(rules)
            try data.write(to: rulesFile)
        } catch {
            print("Failed to save custom rules: \(error)")
        }
    }

    func addRule(_ rule: CustomRule) {
        rules.append(rule)
        saveRules()
    }

    func updateRule(_ rule: CustomRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRules()
        }
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    func toggleRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
            saveRules()
        }
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }

    var enabledRules: [CustomRule] {
        rules.filter(\.isEnabled)
    }

    func matchFile(name: String, size: Int64, modifiedDate: Date?, parentFolder: String) -> CustomRule? {
        return enabledRules.first { $0.matchesFile(name: name, size: size, modifiedDate: modifiedDate, parentFolder: parentFolder) }
    }

    func exportRules() -> Data? {
        return try? JSONEncoder().encode(rules)
    }

    func importRules(from data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode([CustomRule].self, from: data) else { return false }
        rules.append(contentsOf: imported)
        saveRules()
        return true
    }

    static let defaultRules: [CustomRule] = [
        CustomRule(
            name: "Screenshots to Screenshots folder",
            pattern: "Screenshot*",
            destination: "Screenshots"
        ),
        CustomRule(
            name: "DMG installers to Installers",
            pattern: "*.dmg",
            destination: "Installers"
        ),
        CustomRule(
            name: "ZIP archives to Archives",
            pattern: "*.zip",
            destination: "Archives"
        )
    ]
}
