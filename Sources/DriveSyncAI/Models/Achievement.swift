// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct Achievement: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let tier: AchievementTier
    var isUnlocked: Bool
    var unlockedAt: Date?

    init(id: String, name: String, description: String, icon: String, tier: AchievementTier, isUnlocked: Bool = false, unlockedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.tier = tier
        self.isUnlocked = isUnlocked
        self.unlockedAt = unlockedAt
    }
}

enum AchievementTier: String, Codable, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum

    var color: String {
        switch self {
        case .bronze: return "bronze"
        case .silver: return "silver"
        case .gold: return "gold"
        case .platinum: return "platinum"
        }
    }
}
