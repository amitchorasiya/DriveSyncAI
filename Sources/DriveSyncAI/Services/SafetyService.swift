// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor SafetyService {
    static let journalDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".drivesyncai/journal", isDirectory: true)
        return dir
    }()

    private static let backupsSubpath = "backups"
    private static let maxDeleteThreshold = 0.5  // 50%

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var openHandles: [UUID: FileHandle] = [:]

    init() {
        try? fileManager.createDirectory(at: Self.journalDirectory, withIntermediateDirectories: true)
        let backupsDir = Self.journalDirectory.appendingPathComponent(Self.backupsSubpath, isDirectory: true)
        try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }

    func startJob() throws -> UUID {
        let jobId = UUID()
        let journalURL = Self.journalDirectory.appendingPathComponent("\(jobId.uuidString).jsonl")
        guard fileManager.createFile(atPath: journalURL.path, contents: nil) else {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create journal file at \(journalURL.path)"])
        }
        return jobId
    }

    func completeJob(_ jobId: UUID) throws {
        if let handle = openHandles[jobId] {
            try handle.close()
            openHandles.removeValue(forKey: jobId)
        }
    }

    private func journalURL(for jobId: UUID) -> URL {
        Self.journalDirectory.appendingPathComponent("\(jobId.uuidString).jsonl")
    }

    private func backupsDirectory(for jobId: UUID) -> URL {
        Self.journalDirectory.appendingPathComponent(Self.backupsSubpath).appendingPathComponent(jobId.uuidString, isDirectory: true)
    }

    private func fileHandle(for jobId: UUID) throws -> FileHandle {
        if let handle = openHandles[jobId] {
            return handle
        }
        let journalURL = journalURL(for: jobId)
        let handle = try FileHandle(forWritingTo: journalURL)
        handle.seekToEndOfFile()
        openHandles[jobId] = handle
        return handle
    }

    private func appendEntry(_ entry: JournalEntry, jobId: UUID) throws {
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        var line = String(data: data, encoding: .utf8) ?? ""
        if !line.hasSuffix("\n") {
            line += "\n"
        }
        guard let lineData = line.data(using: .utf8) else {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode journal entry"])
        }
        let handle = try fileHandle(for: jobId)
        handle.write(lineData)
        handle.synchronizeFile()
    }

    private func updateEntryStatus(_ entry: JournalEntry, status: JournalEntryStatus, errorMessage: String?, jobId: UUID) throws {
        var updated = entry
        updated.status = status
        updated.errorMessage = errorMessage
        try appendEntry(updated, jobId: jobId)
    }

    func recordCopy(jobId: UUID, source: URL, destination: URL, sourceHash: String?) async throws {
        try checkDeleteSafety(paths: [], totalTargetFiles: 0)
        let entry = JournalEntry(
            id: UUID(),
            jobId: jobId,
            timestamp: Date(),
            action: .copy,
            sourcePath: source.standardized.path,
            destinationPath: destination.standardized.path,
            sourceHash: sourceHash,
            destinationHash: nil,
            backupPath: nil,
            status: .pending,
            errorMessage: nil
        )
        try appendEntry(entry, jobId: jobId)
        do {
            try fileManager.safeCloneOrCopy(from: source, to: destination)
            try updateEntryStatus(entry, status: .completed, errorMessage: nil, jobId: jobId)
        } catch {
            try? updateEntryStatus(entry, status: .failed, errorMessage: error.localizedDescription, jobId: jobId)
            throw error
        }
    }

    func recordOverwrite(jobId: UUID, source: URL, destination: URL, sourceHash: String?, destHash: String?) async throws {
        try checkDeleteSafety(paths: [destination.path], totalTargetFiles: 1)
        let entryId = UUID()
        let backupsDir = backupsDirectory(for: jobId)
        try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let backupURL = backupsDir.appendingPathComponent("\(entryId.uuidString)_\(destination.lastPathComponent)")
        let entry = JournalEntry(
            id: entryId,
            jobId: jobId,
            timestamp: Date(),
            action: .overwrite,
            sourcePath: source.standardized.path,
            destinationPath: destination.standardized.path,
            sourceHash: sourceHash,
            destinationHash: destHash,
            backupPath: backupURL.path,
            status: .pending,
            errorMessage: nil
        )
        try appendEntry(entry, jobId: jobId)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.safeCloneOrCopy(from: destination, to: backupURL)
            }
            try fileManager.removeItem(at: destination)
            try fileManager.safeCloneOrCopy(from: source, to: destination)
            try updateEntryStatus(entry, status: .completed, errorMessage: nil, jobId: jobId)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path), !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.safeCloneOrCopy(from: backupURL, to: destination)
            }
            try? updateEntryStatus(entry, status: .failed, errorMessage: error.localizedDescription, jobId: jobId)
            throw error
        }
    }

    func recordMove(jobId: UUID, source: URL, destination: URL) async throws {
        try checkDeleteSafety(paths: [source.path], totalTargetFiles: 1)
        let entry = JournalEntry(
            id: UUID(),
            jobId: jobId,
            timestamp: Date(),
            action: .move,
            sourcePath: source.standardized.path,
            destinationPath: destination.standardized.path,
            sourceHash: nil,
            destinationHash: nil,
            backupPath: nil,
            status: .pending,
            errorMessage: nil
        )
        try appendEntry(entry, jobId: jobId)
        do {
            let destParent = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: destParent.path) {
                try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
            try updateEntryStatus(entry, status: .completed, errorMessage: nil, jobId: jobId)
        } catch {
            try? updateEntryStatus(entry, status: .failed, errorMessage: error.localizedDescription, jobId: jobId)
            throw error
        }
    }

    func recordDelete(jobId: UUID, target: URL) async throws {
        try checkDeleteSafety(paths: [target.path], totalTargetFiles: 1)
        let targetPath = PathNormalizer.normalize(target.standardized.path)
        guard !PathNormalizer.isProtectedPath(targetPath) else {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete protected path: \(targetPath)"])
        }
        let entryId = UUID()
        let backupsDir = backupsDirectory(for: jobId)
        try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let backupURL = backupsDir.appendingPathComponent("\(entryId.uuidString)_\(target.lastPathComponent)")
        let entry = JournalEntry(
            id: entryId,
            jobId: jobId,
            timestamp: Date(),
            action: .delete,
            sourcePath: target.standardized.path,
            destinationPath: nil,
            sourceHash: nil,
            destinationHash: nil,
            backupPath: backupURL.path,
            status: .pending,
            errorMessage: nil
        )
        try appendEntry(entry, jobId: jobId)
        do {
            try fileManager.safeCloneOrCopy(from: target, to: backupURL)
            try fileManager.removeItem(at: target)
            try updateEntryStatus(entry, status: .completed, errorMessage: nil, jobId: jobId)
        } catch {
            try? updateEntryStatus(entry, status: .failed, errorMessage: error.localizedDescription, jobId: jobId)
            throw error
        }
    }

    func verifyWrite(source: URL, destination: URL, expectedHash: String) async throws {
        let sourceAttrs = try fileManager.attributesOfItem(atPath: source.path)
        let destAttrs = try fileManager.attributesOfItem(atPath: destination.path)
        let sourceSize = (sourceAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        let destSize = (destAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard sourceSize == destSize else {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Size mismatch: source \(sourceSize) vs destination \(destSize)"])
        }
        let actualHash = try await FileHashingService.sha256(of: destination)
        guard actualHash == expectedHash else {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Hash mismatch: expected \(expectedHash) vs actual \(actualHash)"])
        }
    }

    struct IncompleteJob: Sendable {
        let jobId: UUID
        let entries: [JournalEntry]
        let journalURL: URL
    }

    func findIncompleteJobs() throws -> [IncompleteJob] {
        let journalDir = Self.journalDirectory
        guard fileManager.fileExists(atPath: journalDir.path) else {
            return []
        }
        let contents = try fileManager.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        var result: [IncompleteJob] = []
        for journalURL in contents {
            let jobIdString = journalURL.deletingPathExtension().lastPathComponent
            guard let jobId = UUID(uuidString: jobIdString) else { continue }
            let entries = try parseJournalEntries(from: journalURL)
            let pendingEntries = entries.filter { $0.status == .pending || $0.status == .inProgress }
            if !pendingEntries.isEmpty {
                result.append(IncompleteJob(jobId: jobId, entries: pendingEntries, journalURL: journalURL))
            }
        }
        return result
    }

    private func parseJournalEntries(from url: URL) throws -> [JournalEntry] {
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            return []
        }
        var entriesByIndex: [(id: UUID, entry: JournalEntry)] = []
        var seenIds: Set<UUID> = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            do {
                let entry = try decoder.decode(JournalEntry.self, from: lineData)
                if !seenIds.contains(entry.id) {
                    seenIds.insert(entry.id)
                    entriesByIndex.append((entry.id, entry))
                } else {
                    if let idx = entriesByIndex.firstIndex(where: { $0.id == entry.id }) {
                        var updated = entriesByIndex[idx].entry
                        updated.status = entry.status
                        updated.errorMessage = entry.errorMessage
                        entriesByIndex[idx] = (entry.id, updated)
                    }
                }
            } catch {
                continue
            }
        }
        return entriesByIndex.map { $0.entry }
    }

    func rollbackJob(_ jobId: UUID) async throws {
        let journalURL = journalURL(for: jobId)
        guard fileManager.fileExists(atPath: journalURL.path) else {
            return
        }
        let allEntries = try parseJournalEntries(from: journalURL)
        let completedEntries = allEntries.filter { $0.status == .completed }
        for entry in completedEntries.reversed() {
            switch entry.action {
            case .copy:
                if let destPath = entry.destinationPath {
                    let dest = URL(fileURLWithPath: destPath)
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    try updateEntryStatus(entry, status: .rolledBack, errorMessage: nil, jobId: jobId)
                }
            case .overwrite:
                if let destPath = entry.destinationPath, let backupPath = entry.backupPath {
                    let dest = URL(fileURLWithPath: destPath)
                    let backup = URL(fileURLWithPath: backupPath)
                    if fileManager.fileExists(atPath: backup.path) {
                        if fileManager.fileExists(atPath: dest.path) {
                            try fileManager.removeItem(at: dest)
                        }
                        try fileManager.safeCloneOrCopy(from: backup, to: dest)
                    }
                    try updateEntryStatus(entry, status: .rolledBack, errorMessage: nil, jobId: jobId)
                }
            case .move:
                if let destPath = entry.destinationPath {
                    let source = URL(fileURLWithPath: entry.sourcePath)
                    let dest = URL(fileURLWithPath: destPath)
                    if fileManager.fileExists(atPath: dest.path) {
                        if fileManager.fileExists(atPath: source.path) {
                            try fileManager.removeItem(at: source)
                        }
                        try fileManager.moveItem(at: dest, to: source)
                        try updateEntryStatus(entry, status: .rolledBack, errorMessage: nil, jobId: jobId)
                    }
                }
            case .delete:
                if let backupPath = entry.backupPath {
                    let target = URL(fileURLWithPath: entry.sourcePath)
                    let backup = URL(fileURLWithPath: backupPath)
                    if fileManager.fileExists(atPath: backup.path) {
                        let parent = target.deletingLastPathComponent()
                        if !fileManager.fileExists(atPath: parent.path) {
                            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                        }
                        if fileManager.fileExists(atPath: target.path) {
                            try fileManager.removeItem(at: target)
                        }
                        try fileManager.safeCloneOrCopy(from: backup, to: target)
                    }
                    try updateEntryStatus(entry, status: .rolledBack, errorMessage: nil, jobId: jobId)
                }
            }
        }
    }

    func checkDeleteSafety(paths: [String], totalTargetFiles: Int) throws {
        for path in paths {
            let normalized = PathNormalizer.normalize(path)
            if PathNormalizer.isProtectedPath(normalized) {
                throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Protected path cannot be modified: \(normalized)"])
            }
        }
        guard totalTargetFiles > 0 else { return }
        let deleteCount = paths.count
        let ratio = Double(deleteCount) / Double(totalTargetFiles)
        if ratio > Self.maxDeleteThreshold {
            throw NSError(domain: "SafetyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Delete threshold exceeded: \(Int(ratio * 100))% of \(totalTargetFiles) files"])
        }
    }
}
