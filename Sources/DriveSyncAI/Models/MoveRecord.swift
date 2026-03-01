// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct MoveRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let originalPath: String
    let duplicatePath: String
    let movedAt: Date
    let fileHash: String
    let fileSize: UInt64
}

struct DuplicateMoveLog: Codable {
    var records: [MoveRecord]
    let driveRoot: String
    let createdAt: Date

    mutating func addRecord(_ record: MoveRecord) {
        records.append(record)
    }

    func recordsWithinRetention(days: Int) -> [MoveRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return records.filter { $0.movedAt >= cutoff }
    }
}
