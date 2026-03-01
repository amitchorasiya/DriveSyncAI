// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum SyncActionType: String, Codable, CaseIterable, Sendable {
    case create
    case update
    case delete
    case conflict
    case skip
}

enum SyncDirection: String, Codable, CaseIterable, Sendable {
    case oneWayMirror
    case oneWayUpdate
    case bidirectional
}

struct SyncAction: Identifiable, Codable, Sendable {
    let id: UUID
    let actionType: SyncActionType
    let sourceFile: FileInfo?
    let targetFile: FileInfo?
    let relativePath: String
    var isSelected: Bool

    var displayName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var fileSize: UInt64 {
        sourceFile?.size ?? targetFile?.size ?? 0
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
