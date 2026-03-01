// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum ScanMode: String, Codable, CaseIterable, Sendable {
    case quick
    case smart
    case deep
}

enum SmartSelectStrategy: String, Codable, CaseIterable, Sendable {
    case keepOldest
    case keepNewest
    case keepShortestPath
    case manual

    var displayName: String {
        switch self {
        case .keepOldest: return "Keep Oldest"
        case .keepNewest: return "Keep Newest"
        case .keepShortestPath: return "Keep Shortest Path"
        case .manual: return "Manual"
        }
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: UUID
    let hash: String
    var files: [DuplicateFile]
    let totalSize: UInt64

    var duplicateCount: Int {
        max(0, files.count - 1)
    }

    var wastedSpace: UInt64 {
        totalSize * UInt64(duplicateCount)
    }

    var formattedWaste: String {
        ByteCountFormatter.string(fromByteCount: Int64(wastedSpace), countStyle: .file)
    }

    var keptFile: DuplicateFile? {
        files.first { !$0.isSelected }
    }

    var allHaveOneKept: Bool {
        files.contains { !$0.isSelected }
    }
}

struct DuplicateFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileInfo: FileInfo
    var isSelected: Bool
}
