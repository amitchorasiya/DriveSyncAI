// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct FilterService {
    var rules: [FilterRule]

    init(rules: [FilterRule] = FilterRule.defaultExcludes) {
        self.rules = rules
    }

    /// Check if a file should be included based on all active rules.
    /// Logic: file passes if it matches at least one include rule (or no include rules exist)
    /// AND does not match any exclude rule.
    func shouldInclude(relativePath: String) -> Bool {
        let activeRules = rules.filter { $0.isEnabled }
        let includeRules = activeRules.filter { $0.type == .include }
        let excludeRules = activeRules.filter { $0.type == .exclude }

        // If there are include rules, must match at least one
        if !includeRules.isEmpty {
            let matchesInclude = includeRules.contains { $0.matches(relativePath) }
            if !matchesInclude {
                return false
            }
        }

        // Must not match any exclude rule
        if excludeRules.contains(where: { $0.matches(relativePath) }) {
            return false
        }

        return true
    }

    /// Test a pattern against a sample path (for the live test feature in UI)
    static func testPattern(_ pattern: String, against path: String) -> Bool {
        var matchPattern = pattern
        if matchPattern.hasSuffix("/") {
            matchPattern = String(matchPattern.dropLast()) + "/*"
        }

        #if canImport(Darwin) || canImport(Glibc)
        let flags: Int32 = 0
        return path.withCString { pathPtr in
            matchPattern.withCString { patternPtr in
                fnmatch(patternPtr, pathPtr, flags) == 0
            }
        }
        #else
        return FilterService.matchPattern(matchPattern, against: path)
        #endif
    }

    #if !canImport(Darwin) && !canImport(Glibc)
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
    #endif

    /// Save rules to a file
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url)
    }

    /// Load rules from a file
    static func load(from url: URL) throws -> [FilterRule] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([FilterRule].self, from: data)
    }
}
