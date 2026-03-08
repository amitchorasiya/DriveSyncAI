// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import CryptoKit

actor CompareEngine {
    private let scheduler: AdaptiveScheduler
    private let safetyService: SafetyService

    var totalFiles: Int = 0
    var processedFiles: Int = 0
    var currentFile: String = ""

    private static let syncStateDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".drivesyncai/sync_state", isDirectory: true)
    }()

    init(scheduler: AdaptiveScheduler, safetyService: SafetyService) {
        self.scheduler = scheduler
        self.safetyService = safetyService
    }

    /// Compare source and target directories, producing a list of proposed actions.
    /// Does NOT modify any files (dry-run by nature).
    func compare(
        source: URL,
        target: URL,
        direction: SyncDirection,
        sourceDriveInfo: DriveInfo,
        targetDriveInfo: DriveInfo,
        filterRules: [FilterRule] = []
    ) async throws -> [SyncAction] {
        totalFiles = 0
        processedFiles = 0
        currentFile = ""

        let caseSensitive = sourceDriveInfo.isCaseSensitive || targetDriveInfo.isCaseSensitive
        let filterService = FilterService(rules: filterRules)

        let sourceMap = try await scanDirectory(at: source, root: source, caseSensitive: caseSensitive, filterService: filterService)
        let targetMap = try await scanDirectory(at: target, root: target, caseSensitive: caseSensitive, filterService: filterService)

        let allPaths = Set(sourceMap.keys).union(targetMap.keys)
        totalFiles = allPaths.count
        var actions: [SyncAction] = []

        for relPath in allPaths {
            processedFiles += 1
            currentFile = relPath

            let normRelPath = PathNormalizer.normalize(relPath)
            let sourceInfo = findInMap(sourceMap, key: normRelPath, caseSensitive: caseSensitive)
            let targetInfo = findInMap(targetMap, key: normRelPath, caseSensitive: caseSensitive)
            let relativePathForAction = sourceInfo?.relativePath ?? targetInfo?.relativePath ?? relPath

            let action: SyncAction?
            switch direction {
            case .oneWayMirror:
                action = actionForOneWayMirror(
                    source: sourceInfo,
                    target: targetInfo,
                    relativePath: relativePathForAction,
                    caseSensitive: caseSensitive
                )
            case .oneWayUpdate:
                action = actionForOneWayUpdate(
                    source: sourceInfo,
                    target: targetInfo,
                    relativePath: relativePathForAction,
                    caseSensitive: caseSensitive
                )
            case .bidirectional:
                action = try await actionForBidirectional(
                    source: source,
                    target: target,
                    sourceInfo: sourceInfo,
                    targetInfo: targetInfo,
                    relativePath: relativePathForAction,
                    caseSensitive: caseSensitive
                )
            }

            if let a = action {
                actions.append(a)
            }
        }

        processedFiles = totalFiles
        currentFile = ""
        return actions
    }

    private func scanDirectory(at url: URL, root: URL, caseSensitive: Bool, filterService: FilterService) async throws -> [String: FileInfo] {
        let fm = FileManager.default
        let fileURLs = try fm.enumerateFiles(at: url)
        var map: [String: FileInfo] = [:]

        for itemURL in fileURLs {
            do {
                let info = try FileInfo(url: itemURL, relativeTo: root)
                let relPath = info.relativePath
                guard filterService.shouldInclude(relativePath: relPath) else { continue }
                let normPath = PathNormalizer.normalize(relPath)
                let key = caseSensitive ? normPath : normPath.lowercased()
                map[key] = info
            } catch {
                continue
            }
        }

        return map
    }

    private func findInMap(_ map: [String: FileInfo], key: String, caseSensitive: Bool) -> FileInfo? {
        let lookupKey = caseSensitive ? key : key.lowercased()
        return map[lookupKey]
    }

    private func actionForOneWayMirror(
        source: FileInfo?,
        target: FileInfo?,
        relativePath: String,
        caseSensitive: Bool
    ) -> SyncAction? {
        if let src = source, let tgt = target {
            let sameMod = src.modificationDate == tgt.modificationDate
            let sameSize = src.size == tgt.size
            if sameMod && sameSize {
                return SyncAction(id: UUID(), actionType: .skip, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
            }
            return SyncAction(id: UUID(), actionType: .update, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
        }
        if source != nil, target == nil {
            return SyncAction(id: UUID(), actionType: .create, sourceFile: source, targetFile: nil, relativePath: relativePath, isSelected: true)
        }
        if source == nil, target != nil {
            return SyncAction(id: UUID(), actionType: .delete, sourceFile: nil, targetFile: target, relativePath: relativePath, isSelected: true)
        }
        return nil
    }

    private func actionForOneWayUpdate(
        source: FileInfo?,
        target: FileInfo?,
        relativePath: String,
        caseSensitive: Bool
    ) -> SyncAction? {
        if let src = source, let tgt = target {
            if src.modificationDate > tgt.modificationDate {
                return SyncAction(id: UUID(), actionType: .update, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
            }
            return SyncAction(id: UUID(), actionType: .skip, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
        }
        if source != nil, target == nil {
            return SyncAction(id: UUID(), actionType: .create, sourceFile: source, targetFile: nil, relativePath: relativePath, isSelected: true)
        }
        return nil
    }

    private func actionForBidirectional(
        source: URL,
        target: URL,
        sourceInfo: FileInfo?,
        targetInfo: FileInfo?,
        relativePath: String,
        caseSensitive: Bool
    ) async throws -> SyncAction? {
        let stateId = stateIdFor(source: source, target: target)
        let state = loadSyncState(stateId: stateId)

        let srcMod = sourceInfo?.modificationDate
        let tgtMod = targetInfo?.modificationDate
        let stateEntry = state?.files[relativePath] ?? (caseSensitive ? nil : state?.files[relativePath.lowercased()])

        if let src = sourceInfo, let tgt = targetInfo {
            let srcNewer = (srcMod ?? .distantPast) > (tgtMod ?? .distantPast)
            let tgtNewer = (tgtMod ?? .distantPast) > (srcMod ?? .distantPast)

            if let entry = stateEntry {
                let srcChanged = (srcMod ?? .distantPast) > (entry.sourceMod ?? .distantPast)
                let tgtChanged = (tgtMod ?? .distantPast) > (entry.targetMod ?? .distantPast)

                if srcChanged && tgtChanged {
                    return SyncAction(id: UUID(), actionType: .conflict, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: false)
                }
                if srcChanged {
                    return SyncAction(id: UUID(), actionType: .update, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
                }
                if tgtChanged {
                    return SyncAction(id: UUID(), actionType: .update, sourceFile: tgt, targetFile: src, relativePath: relativePath, isSelected: true)
                }
                return SyncAction(id: UUID(), actionType: .skip, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
            }

            if srcNewer {
                return SyncAction(id: UUID(), actionType: .update, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
            }
            if tgtNewer {
                return SyncAction(id: UUID(), actionType: .update, sourceFile: tgt, targetFile: src, relativePath: relativePath, isSelected: true)
            }
            return SyncAction(id: UUID(), actionType: .skip, sourceFile: src, targetFile: tgt, relativePath: relativePath, isSelected: true)
        }

        if sourceInfo != nil, targetInfo == nil {
            return SyncAction(id: UUID(), actionType: .create, sourceFile: sourceInfo, targetFile: nil, relativePath: relativePath, isSelected: true)
        }
        if sourceInfo == nil, targetInfo != nil {
            return SyncAction(id: UUID(), actionType: .create, sourceFile: targetInfo, targetFile: nil, relativePath: relativePath, isSelected: true)
        }

        return nil
    }

    private func stateIdFor(source: URL, target: URL) -> String {
        let combined = source.standardized.path + "|" + target.standardized.path
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private struct SyncStateFile: Codable {
        let sourcePath: String
        let targetPath: String
        let lastSync: Date
        let files: [String: FileStateEntry]
    }

    private struct FileStateEntry: Codable {
        let sourceMod: Date?
        let targetMod: Date?
    }

    private func loadSyncState(stateId: String) -> SyncStateFile? {
        let fm = FileManager.default
        let stateURL = Self.syncStateDirectory.appendingPathComponent("\(stateId).json")
        guard fm.fileExists(atPath: stateURL.path) else { return nil }
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SyncStateFile.self, from: data)
    }

    func saveSyncState(source: URL, target: URL, files: [String: (sourceMod: Date?, targetMod: Date?)]) {
        let stateId = stateIdFor(source: source, target: target)
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.syncStateDirectory, withIntermediateDirectories: true)
        var mergedFiles: [String: FileStateEntry] = [:]
        if let existing = loadSyncState(stateId: stateId) {
            mergedFiles = existing.files
        }
        for (path, mods) in files {
            mergedFiles[path] = FileStateEntry(sourceMod: mods.sourceMod, targetMod: mods.targetMod)
        }
        let state = SyncStateFile(
            sourcePath: source.standardized.path,
            targetPath: target.standardized.path,
            lastSync: Date(),
            files: mergedFiles
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        let stateURL = Self.syncStateDirectory.appendingPathComponent("\(stateId).json")
        try? data.write(to: stateURL)
    }
}
