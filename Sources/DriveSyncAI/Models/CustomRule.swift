// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum RuleCondition: Codable, Equatable {
    case olderThan(days: Int)
    case newerThan(days: Int)
    case largerThan(bytes: Int64)
    case smallerThan(bytes: Int64)
    case inFolder(String)

    var displayDescription: String {
        switch self {
        case .olderThan(let days): return "Older than \(days) days"
        case .newerThan(let days): return "Newer than \(days) days"
        case .largerThan(let bytes): return "Larger than \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .smallerThan(let bytes): return "Smaller than \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .inFolder(let folder): return "In folder: \(folder)"
        }
    }

    func matches(fileSize: Int64, modifiedDate: Date?, parentFolder: String) -> Bool {
        switch self {
        case .olderThan(let days):
            guard let date = modifiedDate else { return false }
            return Date().timeIntervalSince(date) > Double(days) * 86400
        case .newerThan(let days):
            guard let date = modifiedDate else { return false }
            return Date().timeIntervalSince(date) < Double(days) * 86400
        case .largerThan(let bytes):
            return fileSize > bytes
        case .smallerThan(let bytes):
            return fileSize < bytes
        case .inFolder(let folder):
            return parentFolder.contains(folder)
        }
    }
}

struct CustomRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var pattern: String
    var destination: String
    var condition: RuleCondition?
    var isEnabled: Bool = true

    var displaySummary: String {
        var parts = ["\(pattern) → \(destination)"]
        if let cond = condition {
            parts.append(cond.displayDescription)
        }
        return parts.joined(separator: ", ")
    }

    func matchesFile(name: String, size: Int64, modifiedDate: Date?, parentFolder: String) -> Bool {
        guard isEnabled else { return false }
        guard globMatch(pattern: pattern, text: name) else { return false }
        if let cond = condition {
            return cond.matches(fileSize: size, modifiedDate: modifiedDate, parentFolder: parentFolder)
        }
        return true
    }
}

func globMatch(pattern: String, text: String) -> Bool {
    let p = Array(pattern.lowercased())
    let t = Array(text.lowercased())
    var pi = 0, ti = 0
    var starP = -1, starT = -1

    while ti < t.count {
        if pi < p.count && (p[pi] == t[ti] || p[pi] == "?") {
            pi += 1
            ti += 1
        } else if pi < p.count && p[pi] == "*" {
            starP = pi
            starT = ti
            pi += 1
        } else if starP != -1 {
            pi = starP + 1
            starT += 1
            ti = starT
        } else {
            return false
        }
    }
    while pi < p.count && p[pi] == "*" { pi += 1 }
    return pi == p.count
}
