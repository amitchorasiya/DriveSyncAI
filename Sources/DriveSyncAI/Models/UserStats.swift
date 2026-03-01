// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct UserStats: Codable {
    var totalFilesSynced: Int = 0
    var totalBytesSynced: UInt64 = 0
    var totalDuplicatesFound: Int = 0
    var totalSpaceSaved: UInt64 = 0
    var totalSyncsCompleted: Int = 0
    var totalScansCompleted: Int = 0
    var profilesCreated: Int = 0

    var formattedSpaceSaved: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSpaceSaved), countStyle: .file)
    }

    var formattedBytesSynced: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytesSynced), countStyle: .file)
    }
}
