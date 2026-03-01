// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum DriveConnectionType: String, Codable, Sendable, CaseIterable {
    case usb2
    case usb3
    case thunderbolt
    case nvme
    case network
    case internal_ = "internal"
    case unknown
}

struct DriveInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let totalCapacity: UInt64
    let availableCapacity: UInt64
    let connectionType: DriveConnectionType
    let isRemovable: Bool
    let volumeFormat: String
    let isCaseSensitive: Bool

    var usedCapacity: UInt64 {
        totalCapacity >= availableCapacity ? totalCapacity - availableCapacity : 0
    }

    var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity) * 100
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalCapacity), countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: Int64(availableCapacity), countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedCapacity), countStyle: .file)
    }

    var maxConcurrentIO: Int {
        switch connectionType {
        case .usb2: return 1
        case .usb3, .network: return 2
        case .thunderbolt, .nvme: return 4
        case .internal_, .unknown: return 2
        }
    }
}
