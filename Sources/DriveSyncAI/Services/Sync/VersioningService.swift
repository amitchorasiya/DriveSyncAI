// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum VersioningStrategy: String, Codable, CaseIterable {
    case disabled       // No versioning
    case trashCan       // Move to .versions/, auto-cleanup after N days
    case timestamped    // Keep with timestamp suffix (file_2024-01-15_143022.txt)
    case numbered       // Keep last N versions (file.txt.1, file.txt.2, ...)

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .trashCan: return "Trash Can"
        case .timestamped: return "Timestamped"
        case .numbered: return "Numbered"
        }
    }

    var description: String {
        switch self {
        case .disabled: return "No version backups before overwrite or delete"
        case .trashCan: return "Move to .versions/, auto-cleanup after retention period"
        case .timestamped: return "Keep copies with timestamp suffix (file_YYYY-MM-DD_HHmmss.ext)"
        case .numbered: return "Keep last N versions (file.ext.1, file.ext.2, ...)"
        }
    }
}

actor VersioningService {
    private let strategy: VersioningStrategy
    private let maxVersions: Int      // for numbered strategy
    private let retentionDays: Int    // for trashCan strategy
    private let versionsDirectory: URL // .versions/ folder on the target drive
    private let driveRoot: URL        // root used to compute relative paths

    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    init(
        strategy: VersioningStrategy,
        versionsDirectory: URL,
        maxVersions: Int = 5,
        retentionDays: Int = 30
    ) {
        self.strategy = strategy
        self.versionsDirectory = versionsDirectory
        self.maxVersions = maxVersions
        self.retentionDays = retentionDays
        // versionsDirectory is typically .../drive_root/.versions
        self.driveRoot = versionsDirectory.deletingLastPathComponent()
    }

    /// Back up a file before it gets overwritten or deleted.
    /// Returns the backup path, or nil if versioning is disabled.
    func backupBeforeOverwrite(file: URL) async throws -> URL? {
        guard strategy != .disabled else { return nil }
        guard fileManager.fileExists(atPath: file.path) else { return nil }

        let relativePath = relativePath(from: file)
        let versionedPath = versionsDirectory.appendingPathComponent(relativePath)
        let versionedParent = versionedPath.deletingLastPathComponent()
        try fileManager.createDirectory(at: versionedParent, withIntermediateDirectories: true)

        let backupURL: URL
        switch strategy {
        case .disabled:
            return nil

        case .trashCan:
            backupURL = versionedPath
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.safeCloneOrCopy(from: file, to: backupURL)
            return backupURL

        case .timestamped:
            let ext = (file.lastPathComponent as NSString).pathExtension
            let baseName = ext.isEmpty
                ? file.lastPathComponent
                : (file.lastPathComponent as NSString).deletingPathExtension
            let timestamp = dateFormatter.string(from: Date())
            let versionedFileName = ext.isEmpty
                ? "\(baseName)_\(timestamp)"
                : "\(baseName)_\(timestamp).\(ext)"
            backupURL = versionedParent.appendingPathComponent(versionedFileName)
            try fileManager.safeCloneOrCopy(from: file, to: backupURL)
            return backupURL

        case .numbered:
            backupURL = try rotateAndCreateNumbered(versionedParent: versionedParent, file: file)
            return backupURL
        }
    }

    private func relativePath(from file: URL) -> String {
        let filePath = file.standardized.path
        let rootPath = driveRoot.standardized.path
        guard filePath.hasPrefix(rootPath) else {
            return file.lastPathComponent
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let relative = String(filePath.dropFirst(prefix.count))
        return relative.isEmpty ? file.lastPathComponent : relative
    }

    private func rotateAndCreateNumbered(versionedParent: URL, file: URL) throws -> URL {
        let ext = (file.lastPathComponent as NSString).pathExtension
        let baseName = ext.isEmpty
            ? file.lastPathComponent
            : (file.lastPathComponent as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        // Rotate: file.3 -> file.4, file.2 -> file.3, ...
        for i in (1..<maxVersions).reversed() {
            let from = versionedParent.appendingPathComponent("\(baseName).\(i)\(suffix)")
            let to = versionedParent.appendingPathComponent("\(baseName).\(i + 1)\(suffix)")
            if fileManager.fileExists(atPath: from.path) {
                if fileManager.fileExists(atPath: to.path) {
                    try fileManager.removeItem(at: to)
                }
                try fileManager.moveItem(at: from, to: to)
            }
        }

        let backupURL = versionedParent.appendingPathComponent("\(baseName).1\(suffix)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.safeCloneOrCopy(from: file, to: backupURL)
        return backupURL
    }

    /// Clean up old versions based on strategy.
    func cleanupOldVersions() async throws -> Int {
        guard strategy == .trashCan else { return 0 }

        var cleaned = 0
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        guard fileManager.fileExists(atPath: versionsDirectory.path) else { return 0 }

        let enumerator = fileManager.enumerator(
            at: versionsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        var urlsToDelete: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                urlsToDelete.append(url)
            }
        }

        for url in urlsToDelete {
            try? fileManager.removeItem(at: url)
            cleaned += 1
        }

        // Remove empty directories
        try removeEmptyDirectories(from: versionsDirectory)
        return cleaned
    }

    private func removeEmptyDirectories(from url: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        ) else { return }

        var dirs: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                dirs.append(item)
            }
        }

        for dir in dirs.sorted(by: { $0.path.count > $1.path.count }) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            if contents.isEmpty {
                try? fileManager.removeItem(at: dir)
            }
        }
    }

    /// List all versioned files
    func listVersions() async throws -> [(original: String, versions: [URL])] {
        guard fileManager.fileExists(atPath: versionsDirectory.path) else { return [] }

        var result: [(original: String, versions: [URL])] = []
        let enumerator = fileManager.enumerator(
            at: versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var filesByOriginal: [String: [URL]] = [:]

        while let url = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }

            let relPath = url.path.dropFirst(versionsDirectory.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let original = stripVersionSuffix(from: relPath)
            filesByOriginal[original, default: []].append(url)
        }

        for (original, urls) in filesByOriginal {
            result.append((original: original, versions: urls.sorted { $0.path < $1.path }))
        }

        return result.sorted { $0.original < $1.original }
    }

    private func stripVersionSuffix(from relPath: String) -> String {
        let ns = relPath as NSString
        let dirPart = ns.deletingLastPathComponent
        let name = ns.lastPathComponent
        let ext = ns.pathExtension
        var stem = ext.isEmpty ? name : ns.deletingPathExtension

        // Timestamped: file_2024-01-15_143022 -> file
        if let r = stem.range(of: "_", options: .backwards), r.lowerBound > stem.startIndex {
            let suffix = stem[r.upperBound...]
            if suffix.contains("-") && suffix.contains("_") {
                stem = String(stem[..<r.lowerBound])
            }
        }

        // Numbered: file.1 -> file (before ext)
        if let r = stem.range(of: ".", options: .backwards), r.lowerBound > stem.startIndex {
            let suffix = stem[r.upperBound...]
            if suffix.allSatisfy({ $0.isNumber }) {
                stem = String(stem[..<r.lowerBound])
            }
        }

        let baseName = ext.isEmpty ? stem : "\(stem).\(ext)"
        return dirPart.isEmpty ? baseName : (dirPart as NSString).appendingPathComponent(baseName)
    }

    /// Restore a specific version
    func restoreVersion(from backup: URL, to original: URL) async throws {
        let parent = original.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: original.path) {
            try fileManager.removeItem(at: original)
        }
        try fileManager.safeCloneOrCopy(from: backup, to: original)
    }
}
