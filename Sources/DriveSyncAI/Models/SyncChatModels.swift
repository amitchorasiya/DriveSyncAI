// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - LLM Response Model

struct SyncRefinementResponse: Codable {
    var assistantMessage: String?
    var followUpQuestion: String?
    var filterChanges: [SyncFilterChange]?
    var selectionChanges: [SyncSelectionChange]?
    var directionChange: String?
    var expandFolders: [String]?

    enum CodingKeys: String, CodingKey {
        case assistantMessage, followUpQuestion
        case filterChanges, selectionChanges
        case directionChange, expandFolders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantMessage = try? container.decode(String.self, forKey: .assistantMessage)
        followUpQuestion = try? container.decode(String.self, forKey: .followUpQuestion)
        filterChanges = try? container.decode([SyncFilterChange].self, forKey: .filterChanges)
        selectionChanges = try? container.decode([SyncSelectionChange].self, forKey: .selectionChanges)
        directionChange = try? container.decode(String.self, forKey: .directionChange)
        expandFolders = try? container.decode([String].self, forKey: .expandFolders)
    }
}

struct SyncFilterChange: Codable {
    var category: String
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case category, active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        if let boolVal = try? container.decode(Bool.self, forKey: .active) {
            active = boolVal
        } else if let strVal = try? container.decode(String.self, forKey: .active) {
            active = strVal.lowercased() == "true"
        } else {
            active = true
        }
    }
}

struct SyncSelectionChange: Codable {
    var action: String
    var target: String?
    var value: Bool?
    var threshold: String?

    static let validActions: Set<String> = [
        "selectAll", "deselectAll",
        "selectFolder", "deselectFolder",
        "selectByActionType", "deselectByActionType",
        "selectByExtension", "deselectByExtension",
        "selectByCategory", "deselectByCategory",
        "selectByMinSize", "deselectByMinSize",
        "selectByDateAfter", "deselectByDateBefore"
    ]

    enum CodingKeys: String, CodingKey {
        case action, target, value, threshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        target = try? container.decode(String.self, forKey: .target)
        if let boolVal = try? container.decode(Bool.self, forKey: .value) {
            value = boolVal
        } else if let strVal = try? container.decode(String.self, forKey: .value) {
            value = strVal.lowercased() == "true"
        }
        threshold = try? container.decode(String.self, forKey: .threshold)
    }
}

// MARK: - Result for UI consumption

struct SyncRefinementResult {
    var filterChanges: [SyncFilterChange]
    var selectionChanges: [SyncSelectionChange]
    var directionChange: String?
    var expandFolders: [String]
    var summary: String

    var hasChanges: Bool {
        !filterChanges.isEmpty || !selectionChanges.isEmpty || directionChange != nil || !expandFolders.isEmpty
    }

    static let empty = SyncRefinementResult(
        filterChanges: [], selectionChanges: [],
        directionChange: nil, expandFolders: [], summary: ""
    )
}
