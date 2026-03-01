// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum PathNormalizer {
    /// Normalize a path to NFC form for consistent comparison.
    /// macOS HFS+ stores filenames in NFD; APFS uses NFC.
    static func normalize(_ path: String) -> String {
        (path as NSString).precomposedStringWithCanonicalMapping
    }

    /// Compare two paths accounting for case sensitivity of the volume.
    static func pathsAreEqual(_ a: String, _ b: String, caseSensitive: Bool) -> Bool {
        let normA = normalize(a)
        let normB = normalize(b)
        if caseSensitive {
            return normA == normB
        }
        return normA.compare(normB, options: .caseInsensitive) == .orderedSame
    }

    /// Compute a relative path from a file URL to a root URL.
    static func relativePath(of fileURL: URL, to rootURL: URL) -> String {
        let filePath = fileURL.standardized.path
        let rootPath = rootURL.standardized.path
        guard filePath.hasPrefix(rootPath) else {
            return filePath
        }
        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        let remainder = filePath[startIndex...]
        if remainder.isEmpty || remainder == "/" {
            return "."
        }
        if remainder.first == "/" {
            return String(remainder.dropFirst())
        }
        return String(remainder)
    }

    /// Paths that should not be modified for safety.
    static let protectedPaths: Set<String> = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/Applications",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/.Trashes"
    ]

    /// Check if a path falls within a protected system directory.
    static func isProtectedPath(_ path: String) -> Bool {
        let normalized = normalize(path)
        let pathComponents = (normalized as NSString).pathComponents
        for protected in protectedPaths {
            let protectedComponents = (protected as NSString).pathComponents
            guard protectedComponents.count <= pathComponents.count else { continue }
            let prefix = pathComponents.prefix(protectedComponents.count)
            if prefix.elementsEqual(protectedComponents) {
                return true
            }
        }
        return false
    }
}
