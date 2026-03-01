// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - LLM Response Model

struct DuplicateRefinementResponse: Codable {
    var assistantMessage: String?
    var followUpQuestion: String?
    var selectionChanges: [DuplicateSelectionChange]?

    enum CodingKeys: String, CodingKey {
        case assistantMessage, followUpQuestion, selectionChanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantMessage = try? container.decode(String.self, forKey: .assistantMessage)
        followUpQuestion = try? container.decode(String.self, forKey: .followUpQuestion)
        selectionChanges = try? container.decode([DuplicateSelectionChange].self, forKey: .selectionChanges)
    }
}

struct DuplicateSelectionChange: Codable {
    var action: String
    var target: String?
    var threshold: String?

    static let validActions: Set<String> = [
        "selectAll", "deselectAll",
        "smartSelectKeepNewest", "smartSelectKeepOldest",
        "smartSelectKeepShortestPath",
        "selectByCategory", "deselectByCategory",
        "selectByFolder", "deselectByFolder",
        "selectByMinSize",
    ]
}

// MARK: - Result for UI consumption

struct DuplicateRefinementResult {
    var selectionChanges: [DuplicateSelectionChange]
    var summary: String

    var hasChanges: Bool {
        !selectionChanges.isEmpty
    }

    static let empty = DuplicateRefinementResult(selectionChanges: [], summary: "")
}
