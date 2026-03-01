// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

@MainActor
final class OrganizationPreferencesStore: ObservableObject {
    @Published var preferences: OrganizationPreferences = .default

    private let configDir: URL
    private let configFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".drivesyncai", isDirectory: true)
        configFile = configDir.appendingPathComponent("organize_preferences.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: configFile),
              let decoded = try? JSONDecoder().decode(OrganizationPreferences.self, from: data) else {
            preferences = .default
            return
        }
        preferences = decoded
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: configFile)
        } catch {
            print("Failed to save organization preferences: \(error)")
        }
    }
}
