// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum SyncItemStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case skipped
    case paused
}

struct SyncItem: Identifiable, Codable, Sendable {
    let id: UUID
    let action: SyncAction
    var status: SyncItemStatus
    var bytesTransferred: UInt64
    var errorMessage: String?

    var progress: Double {
        let size = action.fileSize
        guard size > 0 else { return 1 }
        return min(1, Double(bytesTransferred) / Double(size))
    }
}
