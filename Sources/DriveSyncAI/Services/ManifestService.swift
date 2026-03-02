// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct ManifestEntry: Codable {
    let relativePath: String
    let size: Int64
    let modifiedDate: Date?
}

struct ManifestComparison {
    var addedFiles: [String] = []
    var removedFiles: [String] = []
    var sizeChangedFiles: [(path: String, before: Int64, after: Int64)] = []
    var unchangedCount: Int = 0

    var isConsistent: Bool {
        removedFiles.isEmpty && sizeChangedFiles.isEmpty
    }

    var summary: String {
        var lines: [String] = []
        lines.append("Manifest Comparison:")
        lines.append("  Unchanged: \(unchangedCount)")
        lines.append("  Added: \(addedFiles.count)")
        lines.append("  Removed: \(removedFiles.count)")
        lines.append("  Size changed: \(sizeChangedFiles.count)")
        if !removedFiles.isEmpty {
            lines.append("\n  Missing files:")
            for f in removedFiles.prefix(20) {
                lines.append("    - \(f)")
            }
            if removedFiles.count > 20 {
                lines.append("    ... and \(removedFiles.count - 20) more")
            }
        }
        return lines.joined(separator: "\n")
    }
}

actor ManifestService {
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func generateManifest(root: URL) async -> [ManifestEntry] {
        let fm = FileManager.default
        var entries: [ManifestEntry] = []

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return entries
        }

        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            let size = Int64(resourceValues?.fileSize ?? 0)
            let modified = resourceValues?.contentModificationDate
            let relativePath = url.path.replacingOccurrences(of: root.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            entries.append(ManifestEntry(relativePath: relativePath, size: size, modifiedDate: modified))
        }

        return entries
    }

    func saveManifest(_ entries: [ManifestEntry], to url: URL) async throws {
        var lines: [String] = []
        lines.append("# Manifest generated \(dateFormatter.string(from: Date()))")
        lines.append("# Total files: \(entries.count)")
        lines.append("# Format: SIZE|PATH")
        lines.append("")

        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            lines.append("\(entry.size)|\(entry.relativePath)")
        }

        let content = lines.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadManifest(from url: URL) async throws -> [ManifestEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var entries: [ManifestEntry] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 2, let size = Int64(parts[0]) else { continue }
            let path = parts.dropFirst().joined(separator: "|")
            entries.append(ManifestEntry(relativePath: path, size: size, modifiedDate: nil))
        }

        return entries
    }

    func compare(before: [ManifestEntry], after: [ManifestEntry]) -> ManifestComparison {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.relativePath, $0.size) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.relativePath, $0.size) })

        var comparison = ManifestComparison()

        for (path, beforeSize) in beforeMap {
            if let afterSize = afterMap[path] {
                if beforeSize == afterSize {
                    comparison.unchangedCount += 1
                } else {
                    comparison.sizeChangedFiles.append((path: path, before: beforeSize, after: afterSize))
                }
            } else {
                comparison.removedFiles.append(path)
            }
        }

        for path in afterMap.keys where beforeMap[path] == nil {
            comparison.addedFiles.append(path)
        }

        comparison.removedFiles.sort()
        comparison.addedFiles.sort()
        return comparison
    }
}
