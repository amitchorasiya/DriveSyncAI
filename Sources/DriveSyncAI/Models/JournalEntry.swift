// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum JournalActionType: String, Codable, Sendable {
    case copy
    case overwrite
    case move
    case delete
}

enum JournalEntryStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case rolledBack
    case interrupted
}

struct JournalEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let jobId: UUID
    let timestamp: Date
    let action: JournalActionType
    let sourcePath: String
    let destinationPath: String?
    let sourceHash: String?
    let destinationHash: String?
    let backupPath: String?
    var status: JournalEntryStatus
    var errorMessage: String?
}
