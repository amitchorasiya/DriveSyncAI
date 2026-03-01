// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Combine

struct AchievementStorage: Codable {
    var achievements: [Achievement]
    var stats: UserStats
}

@MainActor
final class AchievementService: ObservableObject {
    @Published var achievements: [Achievement] = []
    @Published var stats: UserStats = UserStats()
    @Published var recentUnlock: Achievement?

    private static var storageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".drivesyncai", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("achievements.json")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        load()
        registerAchievements()
    }

    func recordSync(fileCount: Int, byteCount: UInt64) {
        stats.totalFilesSynced += fileCount
        stats.totalBytesSynced += byteCount
        stats.totalSyncsCompleted += 1
        checkUnlocks(syncFileCount: fileCount, syncByteCount: byteCount)
        save()
    }

    func recordDuplicatesFound(count: Int, spaceSaved: UInt64) {
        stats.totalDuplicatesFound += count
        stats.totalSpaceSaved += spaceSaved
        checkUnlocks()
        save()
    }

    func recordScanCompleted() {
        stats.totalScansCompleted += 1
        checkUnlocks()
        save()
    }

    func recordProfileCreated() {
        stats.profilesCreated += 1
        checkUnlocks()
        save()
    }

    private func checkUnlocks(syncFileCount: Int = 0, syncByteCount: UInt64 = 0) {
        var newlyUnlocked: Achievement?
        let now = Date()

        for i in achievements.indices {
            guard !achievements[i].isUnlocked else { continue }
            var shouldUnlock = false

            switch achievements[i].id {
            case "first_sync":
                shouldUnlock = stats.totalSyncsCompleted >= 1
            case "century":
                shouldUnlock = stats.totalFilesSynced >= 100
            case "thousand_strong":
                shouldUnlock = stats.totalFilesSynced >= 1_000
            case "ten_thousand":
                shouldUnlock = stats.totalFilesSynced >= 10_000
            case "space_saver":
                shouldUnlock = stats.totalSpaceSaved >= 1_073_741_824 // 1 GB
            case "space_master":
                shouldUnlock = stats.totalSpaceSaved >= 10_737_418_240 // 10 GB
            case "space_legend":
                shouldUnlock = stats.totalSpaceSaved >= 107_374_182_400 // 100 GB
            case "duplicate_hunter":
                shouldUnlock = stats.totalDuplicatesFound >= 100
            case "duplicate_slayer":
                shouldUnlock = stats.totalDuplicatesFound >= 1_000
            case "organized":
                shouldUnlock = stats.profilesCreated >= 5
            case "first_scan":
                shouldUnlock = stats.totalScansCompleted >= 1
            case "speed_demon":
                shouldUnlock = syncByteCount >= 1_073_741_824 // 1 GB in one session
            default:
                break
            }

            if shouldUnlock {
                achievements[i].isUnlocked = true
                achievements[i].unlockedAt = now
                if newlyUnlocked == nil {
                    newlyUnlocked = achievements[i]
                }
            }
        }

        if let unlocked = newlyUnlocked {
            recentUnlock = unlocked
        }
    }

    private func registerAchievements() {
        let definitions: [Achievement] = [
            Achievement(id: "first_sync", name: "First Sync", description: "Complete your first sync", icon: "arrow.triangle.2.circlepath", tier: .bronze),
            Achievement(id: "century", name: "Century", description: "Sync 100 files", icon: "doc.on.doc.fill", tier: .bronze),
            Achievement(id: "thousand_strong", name: "Thousand Strong", description: "Sync 1,000 files", icon: "folder.fill.badge.plus", tier: .silver),
            Achievement(id: "ten_thousand", name: "Ten Thousand", description: "Sync 10,000 files", icon: "tray.full.fill", tier: .gold),
            Achievement(id: "space_saver", name: "Space Saver", description: "Free up 1 GB", icon: "externaldrive.fill.badge.minus", tier: .bronze),
            Achievement(id: "space_master", name: "Space Master", description: "Free up 10 GB", icon: "externaldrive.fill.badge.checkmark", tier: .silver),
            Achievement(id: "space_legend", name: "Space Legend", description: "Free up 100 GB", icon: "crown.fill", tier: .gold),
            Achievement(id: "duplicate_hunter", name: "Duplicate Hunter", description: "Find 100 duplicates", icon: "magnifyingglass", tier: .bronze),
            Achievement(id: "duplicate_slayer", name: "Duplicate Slayer", description: "Find 1,000 duplicates", icon: "shield.checkered", tier: .silver),
            Achievement(id: "organized", name: "Organized", description: "Create 5 sync profiles", icon: "folder.badge.gearshape", tier: .silver),
            Achievement(id: "first_scan", name: "First Scan", description: "Complete your first duplicate scan", icon: "doc.text.magnifyingglass", tier: .bronze),
            Achievement(id: "speed_demon", name: "Speed Demon", description: "Sync over 1 GB in one session", icon: "bolt.fill", tier: .silver)
        ]

        if achievements.isEmpty {
            achievements = definitions
        } else {
            var merged = achievements
            for def in definitions {
                if let idx = merged.firstIndex(where: { $0.id == def.id }) {
                    merged[idx] = Achievement(
                        id: def.id,
                        name: def.name,
                        description: def.description,
                        icon: def.icon,
                        tier: def.tier,
                        isUnlocked: merged[idx].isUnlocked,
                        unlockedAt: merged[idx].unlockedAt
                    )
                } else {
                    merged.append(def)
                }
            }
            achievements = merged.sorted { $0.id < $1.id }
        }
    }

    func save() {
        let storage = AchievementStorage(achievements: achievements, stats: stats)
        do {
            let data = try encoder.encode(storage)
            try data.write(to: Self.storageURL)
        } catch {}
    }

    func load() {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let storage = try decoder.decode(AchievementStorage.self, from: data)
            achievements = storage.achievements
            stats = storage.stats
        } catch {
            achievements = []
            stats = UserStats()
        }
    }
}
