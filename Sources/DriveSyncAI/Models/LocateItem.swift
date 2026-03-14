// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct LocateItem: Codable, Identifiable, Sendable {
    let id: UUID
    let imagePath: String
    let labels: [String]
    let place: String?
    let capturedAt: Date
    
    var fullImagePath: URL {
        LocateMyStuffService.storageDir.appendingPathComponent("photos").appendingPathComponent(imagePath)
    }
}
