// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct SyncProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var sourceURL: URL
    var targetURL: URL
    var direction: SyncDirection
    var conflictStrategy: ConflictResolutionStrategy
    var versioningStrategy: VersioningStrategy
    var filterRules: [FilterRule]
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        sourceURL: URL,
        targetURL: URL,
        direction: SyncDirection = .oneWayUpdate,
        conflictStrategy: ConflictResolutionStrategy = .keepBoth,
        versioningStrategy: VersioningStrategy = .disabled,
        filterRules: [FilterRule] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.direction = direction
        self.conflictStrategy = conflictStrategy
        self.versioningStrategy = versioningStrategy
        self.filterRules = filterRules
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - SyncProfileManager

@MainActor
final class SyncProfileManager: ObservableObject {
    @Published var profiles: [SyncProfile] = []

    private weak var achievementService: AchievementService?

    private static var storageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".drivesyncai", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(achievementService: AchievementService? = nil) {
        self.achievementService = achievementService
        load()
    }

    func save(_ profile: SyncProfile) {
        var updated = profile
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            updated.lastUsedAt = profile.lastUsedAt ?? Date()
            profiles[idx] = updated
        } else {
            profiles.append(updated)
            achievementService?.recordProfileCreated()
        }
        persist()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    func load() {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            profiles = try decoder.decode([SyncProfile].self, from: data)
        } catch {
            profiles = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: Self.storageURL)
        } catch {}
    }

    func applyProfile(_ profile: SyncProfile, to syncService: SyncService) {
        syncService.sourceURL = profile.sourceURL
        syncService.targetURL = profile.targetURL
        syncService.direction = profile.direction
        syncService.conflictStrategy = profile.conflictStrategy
        syncService.versioningStrategy = profile.versioningStrategy
        syncService.filterRules = profile.filterRules

        var updated = profile
        updated.lastUsedAt = Date()
        save(updated)
    }

    func createProfileFromCurrent(_ name: String, syncService: SyncService) -> SyncProfile {
        let profile = SyncProfile(
            name: name,
            sourceURL: syncService.sourceURL ?? URL(fileURLWithPath: "/"),
            targetURL: syncService.targetURL ?? URL(fileURLWithPath: "/"),
            direction: syncService.direction,
            conflictStrategy: syncService.conflictStrategy,
            versioningStrategy: syncService.versioningStrategy,
            filterRules: syncService.filterRules
        )
        save(profile)
        return profile
    }
}
