// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct SimilarGroup: Identifiable {
    let id: UUID
    let referenceFile: FileInfo
    var similarFiles: [SimilarFile]
    let similarityReason: SimilarityReason

    var totalWaste: UInt64 { similarFiles.reduce(0) { $0 + $1.fileInfo.size } }
    var formattedWaste: String { ByteCountFormatter.string(fromByteCount: Int64(totalWaste), countStyle: .file) }
}

struct SimilarFile: Identifiable, Hashable {
    let id: UUID
    let fileInfo: FileInfo
    var isSelected: Bool
    let similarity: Double
}

enum SimilarityReason: String, Codable {
    case similarName
    case similarSize
    case sameNameDiffExt
    case nearbyDate

    var displayName: String {
        switch self {
        case .similarName: return "Similar Name"
        case .similarSize: return "Similar Size"
        case .sameNameDiffExt: return "Same Name, Different Extension"
        case .nearbyDate: return "Nearby Date"
        }
    }
}
