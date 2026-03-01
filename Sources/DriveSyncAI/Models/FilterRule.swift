// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum FilterRuleType: String, Codable, CaseIterable {
    case include, exclude
}

struct FilterRule: Identifiable, Codable, Hashable {
    let id: UUID
    var type: FilterRuleType
    var pattern: String
    var isEnabled: Bool
    var description: String

    init(
        id: UUID = UUID(),
        type: FilterRuleType,
        pattern: String,
        isEnabled: Bool = true,
        description: String = ""
    ) {
        self.id = id
        self.type = type
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.description = description.isEmpty ? pattern : description
    }

    /// Test if a given relative path matches this filter rule.
    /// Supports wildcards: * (any chars), ? (single char)
    /// Uses fnmatch-style pattern matching.
    func matches(_ relativePath: String) -> Bool {
        guard isEnabled else { return false }

        var matchPattern = pattern
        // If pattern ends with /, match the directory and everything under it
        if matchPattern.hasSuffix("/") {
            matchPattern = String(matchPattern.dropLast()) + "/*"
        }

        #if canImport(Darwin) || canImport(Glibc)
        let flags: Int32 = 0
        return relativePath.withCString { pathPtr in
            matchPattern.withCString { patternPtr in
                fnmatch(patternPtr, pathPtr, flags) == 0
            }
        }
        #else
        return Self.matchPattern(matchPattern, against: relativePath)
        #endif
    }

    /// Fallback manual wildcard matching when fnmatch is unavailable
    private static func matchPattern(_ pattern: String, against path: String) -> Bool {
        var pIdx = pattern.startIndex
        var sIdx = path.startIndex
        var starP: String.Index?
        var starS: String.Index?

        while sIdx < path.endIndex {
            if pIdx < pattern.endIndex {
                let pc = pattern[pIdx]
                let sc = path[sIdx]
                if pc == "*" {
                    starP = pattern.index(after: pIdx)
                    starS = sIdx
                    pIdx = starP!
                    continue
                }
                if pc == "?" || pc == sc {
                    pIdx = pattern.index(after: pIdx)
                    sIdx = path.index(after: sIdx)
                    continue
                }
            }
            if let sp = starP, let ss = starS {
                pIdx = sp
                let nextS = path.index(after: ss)
                sIdx = nextS
                starS = nextS
                continue
            }
            return false
        }

        while pIdx < pattern.endIndex && pattern[pIdx] == "*" {
            pIdx = pattern.index(after: pIdx)
        }
        return pIdx == pattern.endIndex
    }

    /// Default exclude rules for common macOS junk
    static var defaultExcludes: [FilterRule] {
        [
            FilterRule(type: .exclude, pattern: "*/.DS_Store", description: "macOS metadata files"),
            FilterRule(type: .exclude, pattern: "*/.Trashes", description: "Trash folders"),
            FilterRule(type: .exclude, pattern: "*/node_modules/*", description: "Node.js dependencies"),
            FilterRule(type: .exclude, pattern: "*/.git/*", description: "Git metadata"),
            FilterRule(type: .exclude, pattern: "*/__pycache__/*", description: "Python cache"),
            FilterRule(type: .exclude, pattern: "*/Thumbs.db", description: "Windows thumbnail cache"),
        ]
    }
}
