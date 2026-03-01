// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Combine

@MainActor
final class DuplicateFinderService: ObservableObject {
    // Configuration
    @Published var targetDrive: DriveInfo?
    @Published var scanMode: ScanMode = .smart
    @Published var selectStrategy: SmartSelectStrategy = .keepOldest
    @Published var includedCategories: Set<FileCategory> = Set(FileCategory.allCases)
    @Published var excludeSystemFiles: Bool = true
    @Published var excludeHiddenFiles: Bool = true
    @Published var parallelIOEnabled: Bool = false

    // State
    @Published var state: ScanState = .idle
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var similarGroups: [SimilarGroup] = []
    @Published var progress: ScanProgress = .init()
    @Published var errors: [ScanError] = []

    enum ScanState: Equatable {
        case idle
        case scanning
        case results
        case moving
        case completed
    }

    enum FileCategory: String, CaseIterable, Hashable {
        case photos
        case videos
        case documents
        case music
        case archives
        case other

        var displayName: String {
            switch self {
            case .photos: return "Photos"
            case .videos: return "Videos"
            case .documents: return "Documents"
            case .music: return "Music"
            case .archives: return "Archives"
            case .other: return "Other"
            }
        }

        var extensions: Set<String> {
            switch self {
            case .photos:
                return ["jpg", "jpeg", "png", "heic", "heif", "raw", "cr2", "nef", "tiff", "bmp", "gif", "webp", "svg"]
            case .videos:
                return ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
            case .documents:
                return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "pages", "numbers", "keynote"]
            case .music:
                return ["mp3", "aac", "flac", "wav", "m4a", "ogg", "wma", "aiff"]
            case .archives:
                return ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "iso"]
            case .other:
                return []
            }
        }

        static func category(for fileExtension: String) -> FileCategory {
            let ext = fileExtension.lowercased()
            for category in FileCategory.allCases where category != .other {
                if category.extensions.contains(ext) {
                    return category
                }
            }
            return .other
        }
    }

    struct ScanProgress {
        var phase: String = ""
        var totalFiles: Int = 0
        var processedFiles: Int = 0
        var duplicatesFound: Int = 0
        var spaceRecoverable: UInt64 = 0
        var currentFile: String = ""

        var percentage: Double {
            guard totalFiles > 0 else { return 0 }
            return Double(processedFiles) / Double(totalFiles) * 100
        }
    }

    struct ScanError: Identifiable {
        let id: UUID
        let filePath: String
        let message: String
    }

    private let safetyService: SafetyService
    private let scheduler: AdaptiveScheduler
    private weak var achievementService: AchievementService?
    private let similarFilesService: SimilarFilesService
    private var scanTask: Task<Void, Never>?
    private var lastMovedCount: Int = 0

    init(safetyService: SafetyService, scheduler: AdaptiveScheduler, achievementService: AchievementService? = nil) {
        self.safetyService = safetyService
        self.scheduler = scheduler
        self.achievementService = achievementService
        self.similarFilesService = SimilarFilesService(scheduler: scheduler)
    }

    /// Start scanning for duplicates
    func startScan() async {
        guard let drive = targetDrive else { return }
        guard state != .scanning else { return }

        scanTask?.cancel()
        errors = []
        duplicateGroups = []
        similarGroups = []
        state = .scanning
        progress = ScanProgress(phase: "Starting...", totalFiles: 0, processedFiles: 0, duplicatesFound: 0, spaceRecoverable: 0, currentFile: "")

        let driveRoot = drive.url
        scanTask = Task {
            do {
                await scheduler.updateIOLimit(for: [drive])
                duplicateGroups = try await runScanPipeline(driveRoot: driveRoot)
                if !Task.isCancelled {
                    state = .results
                    progress.phase = "Complete"
                    progress.duplicatesFound = duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
                    progress.spaceRecoverable = duplicateGroups.reduce(0) { $0 + $1.wastedSpace }
                    achievementService?.recordScanCompleted()
                } else {
                    state = .idle
                }
            } catch {
                if !Task.isCancelled {
                    errors.append(ScanError(id: UUID(), filePath: driveRoot.path, message: error.localizedDescription))
                    state = .results
                } else {
                    state = .idle
                }
            }
        }

        await scanTask?.value
    }

    /// Cancel ongoing scan
    func cancelScan() {
        scanTask?.cancel()
        if state == .scanning {
            state = .idle
        }
    }

    /// Apply smart selection strategy to all groups
    func applySmartSelect(_ strategy: SmartSelectStrategy) {
        for i in duplicateGroups.indices {
            let group = duplicateGroups[i]
            let files = group.files
            guard !files.isEmpty else { continue }

            var updatedFiles: [DuplicateFile] = []
            switch strategy {
            case .keepOldest:
                let sorted = files.sorted { $0.fileInfo.modificationDate < $1.fileInfo.modificationDate }
                for (idx, dup) in sorted.enumerated() {
                    updatedFiles.append(DuplicateFile(id: dup.id, fileInfo: dup.fileInfo, isSelected: idx != 0))
                }
            case .keepNewest:
                let sorted = files.sorted { $0.fileInfo.modificationDate > $1.fileInfo.modificationDate }
                for (idx, dup) in sorted.enumerated() {
                    updatedFiles.append(DuplicateFile(id: dup.id, fileInfo: dup.fileInfo, isSelected: idx != 0))
                }
            case .keepShortestPath:
                let sorted = files.sorted { $0.fileInfo.relativePath.components(separatedBy: "/").count < $1.fileInfo.relativePath.components(separatedBy: "/").count }
                for (idx, dup) in sorted.enumerated() {
                    updatedFiles.append(DuplicateFile(id: dup.id, fileInfo: dup.fileInfo, isSelected: idx != 0))
                }
            case .manual:
                for dup in files {
                    updatedFiles.append(DuplicateFile(id: dup.id, fileInfo: dup.fileInfo, isSelected: false))
                }
            }
            duplicateGroups[i] = DuplicateGroup(id: group.id, hash: group.hash, files: updatedFiles, totalSize: group.totalSize)
        }
    }

    /// Toggle selection of a specific file in a group
    func toggleFile(groupId: UUID, fileId: UUID) {
        guard let groupIdx = duplicateGroups.firstIndex(where: { $0.id == groupId }) else { return }
        guard let fileIdx = duplicateGroups[groupIdx].files.firstIndex(where: { $0.id == fileId }) else { return }

        let current = duplicateGroups[groupIdx].files[fileIdx]
        let updated = DuplicateFile(id: current.id, fileInfo: current.fileInfo, isSelected: !current.isSelected)
        duplicateGroups[groupIdx].files[fileIdx] = updated
    }

    /// Toggle selection of a similar file
    func toggleSimilarFile(groupId: UUID, fileId: UUID) {
        guard let groupIdx = similarGroups.firstIndex(where: { $0.id == groupId }) else { return }
        guard let fileIdx = similarGroups[groupIdx].similarFiles.firstIndex(where: { $0.id == fileId }) else { return }
        let current = similarGroups[groupIdx].similarFiles[fileIdx]
        let updated = SimilarFile(id: current.id, fileInfo: current.fileInfo, isSelected: !current.isSelected, similarity: current.similarity)
        similarGroups[groupIdx].similarFiles[fileIdx] = updated
    }

    /// Move selected duplicates to Duplicates folder, preserving structure
    /// Returns number of files moved
    func moveDuplicates() async -> Int {
        guard let drive = targetDrive else { return 0 }
        guard canMoveDuplicates else { return 0 }
        guard state == .results || state == .completed else { return 0 }

        state = .moving
        let driveRoot = drive.url
        let duplicatesRoot = driveRoot.appendingPathComponent("Duplicates", isDirectory: true)
        let moveLogURL = duplicatesRoot.appendingPathComponent(".move_log.json", isDirectory: false)

        var filesToMove: [(DuplicateFile, DuplicateGroup)] = []
        for group in duplicateGroups {
            for dup in group.files where dup.isSelected {
                filesToMove.append((dup, group))
            }
        }

        guard !filesToMove.isEmpty else {
            state = .results
            return 0
        }

        let jobId: UUID
        do {
            jobId = try await safetyService.startJob()
        } catch {
            errors.append(ScanError(id: UUID(), filePath: "", message: "Failed to start move job: \(error.localizedDescription)"))
            state = .results
            return 0
        }

        var moveLog: DuplicateMoveLog
        if FileManager.default.fileExists(atPath: moveLogURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let data = try Data(contentsOf: moveLogURL)
                moveLog = try decoder.decode(DuplicateMoveLog.self, from: data)
            } catch {
                moveLog = DuplicateMoveLog(records: [], driveRoot: driveRoot.path, createdAt: Date())
            }
        } else {
            moveLog = DuplicateMoveLog(records: [], driveRoot: driveRoot.path, createdAt: Date())
        }

        // Prepare move plan (sequential -- resolves destination collisions)
        var movePlan: [(source: URL, dest: URL, hash: String, size: UInt64)] = []
        var reservedPaths: Set<String> = []

        for (dupFile, group) in filesToMove {
            let sourceURL = dupFile.fileInfo.url
            let relPath = dupFile.fileInfo.relativePath
            var destURL = duplicatesRoot.appendingPathComponent(relPath, isDirectory: false)

            var sourceHash = group.hash
            if group.hash.hasPrefix("quick_") {
                do {
                    sourceHash = try await FileHashingService.sha256(of: sourceURL)
                } catch {
                    errors.append(ScanError(id: UUID(), filePath: sourceURL.path, message: "Failed to hash: \(error.localizedDescription)"))
                    continue
                }
            }

            if FileManager.default.fileExists(atPath: destURL.path) || reservedPaths.contains(destURL.path) {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let existingHash = try? await FileHashingService.sha256(of: destURL)
                    if let existing = existingHash, existing == sourceHash {
                        continue
                    }
                }
                var counter = 1
                let baseName = destURL.deletingPathExtension().lastPathComponent
                let ext = destURL.pathExtension
                repeat {
                    let suffix = ext.isEmpty ? " (\(counter))" : " (\(counter)).\(ext)"
                    destURL = destURL.deletingLastPathComponent().appendingPathComponent(baseName + suffix, isDirectory: false)
                    counter += 1
                } while FileManager.default.fileExists(atPath: destURL.path) || reservedPaths.contains(destURL.path)
            }

            reservedPaths.insert(destURL.path)
            movePlan.append((source: sourceURL, dest: destURL, hash: sourceHash, size: dupFile.fileInfo.size))
        }

        // Execute moves (parallel or sequential)
        var movedCount = 0
        var recordsToAdd: [MoveRecord] = []

        if parallelIOEnabled && movePlan.count > 1 {
            let moveItems = movePlan.map { SendableMoveItem(source: $0.source, dest: $0.dest, hash: $0.hash, size: $0.size) }
            let resultCollector = MoveResultCollector()
            let moveErrorCollector = DupErrorCollector()

            do {
                _ = try await scheduler.runParallelIO(items: moveItems) { [safetyService] item in
                    do {
                        try await safetyService.recordMove(jobId: jobId, source: item.source, destination: item.dest)
                        let record = MoveRecord(
                            id: UUID(),
                            originalPath: item.source.standardized.path,
                            duplicatePath: item.dest.standardized.path,
                            movedAt: Date(),
                            fileHash: item.hash,
                            fileSize: item.size
                        )
                        await resultCollector.add(record)
                    } catch {
                        await moveErrorCollector.add(ScanError(id: UUID(), filePath: item.source.path, message: error.localizedDescription))
                    }
                }
            } catch {
                errors.append(ScanError(id: UUID(), filePath: "", message: error.localizedDescription))
            }

            recordsToAdd = await resultCollector.records
            movedCount = recordsToAdd.count
            let collectedErrors = await moveErrorCollector.errors
            errors.append(contentsOf: collectedErrors)
        } else {
            for item in movePlan {
                do {
                    try await safetyService.recordMove(jobId: jobId, source: item.source, destination: item.dest)
                    let record = MoveRecord(
                        id: UUID(),
                        originalPath: item.source.standardized.path,
                        duplicatePath: item.dest.standardized.path,
                        movedAt: Date(),
                        fileHash: item.hash,
                        fileSize: item.size
                    )
                    recordsToAdd.append(record)
                    movedCount += 1
                } catch {
                    errors.append(ScanError(id: UUID(), filePath: item.source.path, message: error.localizedDescription))
                }
            }
        }

        for record in recordsToAdd {
            moveLog.addRecord(record)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            if !FileManager.default.fileExists(atPath: duplicatesRoot.path) {
                try FileManager.default.createDirectory(at: duplicatesRoot, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(moveLog)
            try data.write(to: moveLogURL)
        } catch {
            errors.append(ScanError(id: UUID(), filePath: moveLogURL.path, message: "Failed to write move log: \(error.localizedDescription)"))
        }

        do {
            try await safetyService.completeJob(jobId)
        } catch {
            errors.append(ScanError(id: UUID(), filePath: "", message: "Failed to complete job: \(error.localizedDescription)"))
        }

        lastMovedCount = movedCount

        let spaceSaved = filesToMove.reduce(UInt64(0)) { $0 + $1.0.fileInfo.size }
        achievementService?.recordDuplicatesFound(count: movedCount, spaceSaved: spaceSaved)

        var updatedGroups: [DuplicateGroup] = []
        for group in duplicateGroups {
            let remaining = group.files.filter { !$0.isSelected }
            if remaining.count > 1 {
                updatedGroups.append(DuplicateGroup(id: group.id, hash: group.hash, files: remaining, totalSize: group.totalSize))
            }
        }
        duplicateGroups = updatedGroups

        state = movedCount > 0 ? .completed : .results
        return movedCount
    }

    /// Undo the last move operation
    func undoLastMove() async -> Int {
        guard let drive = targetDrive else { return 0 }
        guard lastMovedCount > 0 else { return 0 }

        let driveRoot = drive.url
        let duplicatesRoot = driveRoot.appendingPathComponent("Duplicates", isDirectory: true)
        let moveLogURL = duplicatesRoot.appendingPathComponent(".move_log.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: moveLogURL.path) else { return 0 }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var moveLog: DuplicateMoveLog
        do {
            let data = try Data(contentsOf: moveLogURL)
            moveLog = try decoder.decode(DuplicateMoveLog.self, from: data)
        } catch {
            return 0
        }

        let recordsToUndo = Array(moveLog.records.suffix(lastMovedCount))
        guard !recordsToUndo.isEmpty else { return 0 }

        let jobId: UUID
        do {
            jobId = try await safetyService.startJob()
        } catch {
            return 0
        }

        var undoneCount = 0
        for record in recordsToUndo.reversed() {
            let sourceURL = URL(fileURLWithPath: record.duplicatePath)
            let destURL = URL(fileURLWithPath: record.originalPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            do {
                try await safetyService.recordMove(jobId: jobId, source: sourceURL, destination: destURL)
                undoneCount += 1
            } catch {
                errors.append(ScanError(id: UUID(), filePath: sourceURL.path, message: error.localizedDescription))
            }
        }

        moveLog.records.removeLast(min(lastMovedCount, moveLog.records.count))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(moveLog) {
            try? data.write(to: moveLogURL)
        }

        do {
            try await safetyService.completeJob(jobId)
        } catch {}

        lastMovedCount = 0
        return undoneCount
    }

    /// Move selected similar files to Duplicates folder
    func moveSimilarFiles() async -> Int {
        guard let drive = targetDrive else { return 0 }
        guard state == .results || state == .completed else { return 0 }

        state = .moving
        let driveRoot = drive.url
        let duplicatesRoot = driveRoot.appendingPathComponent("Duplicates", isDirectory: true)
        let moveLogURL = duplicatesRoot.appendingPathComponent(".move_log.json", isDirectory: false)

        var filesToMove: [SimilarFile] = []
        for group in similarGroups {
            for sf in group.similarFiles where sf.isSelected {
                filesToMove.append(sf)
            }
        }

        guard !filesToMove.isEmpty else {
            state = .results
            return 0
        }

        let jobId: UUID
        do {
            jobId = try await safetyService.startJob()
        } catch {
            errors.append(ScanError(id: UUID(), filePath: "", message: "Failed to start move job: \(error.localizedDescription)"))
            state = .results
            return 0
        }

        var moveLog: DuplicateMoveLog
        if FileManager.default.fileExists(atPath: moveLogURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let data = try Data(contentsOf: moveLogURL)
                moveLog = try decoder.decode(DuplicateMoveLog.self, from: data)
            } catch {
                moveLog = DuplicateMoveLog(records: [], driveRoot: driveRoot.path, createdAt: Date())
            }
        } else {
            moveLog = DuplicateMoveLog(records: [], driveRoot: driveRoot.path, createdAt: Date())
        }

        var movedCount = 0
        for sf in filesToMove {
            let sourceURL = sf.fileInfo.url
            let relPath = sf.fileInfo.relativePath
            var destURL = duplicatesRoot.appendingPathComponent(relPath, isDirectory: false)

            if FileManager.default.fileExists(atPath: destURL.path) {
                var counter = 1
                let baseName = destURL.deletingPathExtension().lastPathComponent
                let ext = destURL.pathExtension
                repeat {
                    let suffix = ext.isEmpty ? " (\(counter))" : " (\(counter)).\(ext)"
                    destURL = destURL.deletingLastPathComponent().appendingPathComponent(baseName + suffix, isDirectory: false)
                    counter += 1
                } while FileManager.default.fileExists(atPath: destURL.path)
            }

            do {
                try await safetyService.recordMove(jobId: jobId, source: sourceURL, destination: destURL)
                let record = MoveRecord(
                    id: UUID(),
                    originalPath: sourceURL.standardized.path,
                    duplicatePath: destURL.standardized.path,
                    movedAt: Date(),
                    fileHash: "similar_\(sf.id.uuidString)",
                    fileSize: sf.fileInfo.size
                )
                moveLog.addRecord(record)
                movedCount += 1
            } catch {
                errors.append(ScanError(id: UUID(), filePath: sourceURL.path, message: error.localizedDescription))
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            if !FileManager.default.fileExists(atPath: duplicatesRoot.path) {
                try FileManager.default.createDirectory(at: duplicatesRoot, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(moveLog)
            try data.write(to: moveLogURL)
        } catch {
            errors.append(ScanError(id: UUID(), filePath: moveLogURL.path, message: "Failed to write move log: \(error.localizedDescription)"))
        }

        do {
            try await safetyService.completeJob(jobId)
        } catch {
            errors.append(ScanError(id: UUID(), filePath: "", message: "Failed to complete job: \(error.localizedDescription)"))
        }

        let spaceSaved = filesToMove.reduce(UInt64(0)) { $0 + $1.fileInfo.size }
        achievementService?.recordDuplicatesFound(count: movedCount, spaceSaved: spaceSaved)

        var updatedGroups: [SimilarGroup] = []
        for group in similarGroups {
            let remaining = group.similarFiles.filter { !$0.isSelected }
            if !remaining.isEmpty {
                updatedGroups.append(SimilarGroup(
                    id: group.id,
                    referenceFile: group.referenceFile,
                    similarFiles: remaining,
                    similarityReason: group.similarityReason
                ))
            }
        }
        similarGroups = updatedGroups

        state = movedCount > 0 ? .completed : .results
        return movedCount
    }

    /// Check if move is safe (every group has at least one kept file)
    var canMoveDuplicates: Bool {
        duplicateGroups.allSatisfy { $0.allHaveOneKept }
    }

    /// Total selected files count and size
    var selectedCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.files.filter(\.isSelected).count }
    }

    var selectedSize: UInt64 {
        duplicateGroups.reduce(0) { total, group in
            total + group.files.filter(\.isSelected).reduce(0) { $0 + $1.fileInfo.size }
        }
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(selectedSize), countStyle: .file)
    }

    // MARK: - Private Scan Pipeline

    private func runScanPipeline(driveRoot: URL) async throws -> [DuplicateGroup] {
        try Task.checkCancellation()

        let fm = FileManager.default
        progress.phase = "Enumerating"
        progress.currentFile = ""

        let urls = try fm.enumerateFiles(
            at: driveRoot,
            skipPackages: true,
            skipHidden: excludeHiddenFiles
        )

        var fileInfos: [FileInfo] = []
        for url in urls {
            try Task.checkCancellation()
            if excludeSystemFiles && PathNormalizer.isProtectedPath(url.standardized.path) {
                continue
            }
            let ext = url.pathExtension
            let category = FileCategory.category(for: ext)
            guard includedCategories.contains(category) else { continue }
            do {
                let info = try FileInfo(url: url, relativeTo: driveRoot)
                fileInfos.append(info)
            } catch {
                errors.append(ScanError(id: UUID(), filePath: url.path, message: error.localizedDescription))
            }
        }

        progress.totalFiles = fileInfos.count
        progress.processedFiles = 0
        try Task.checkCancellation()

        progress.phase = "Grouping by size"
        var sizeGroups: [UInt64: [FileInfo]] = [:]
        for info in fileInfos {
            sizeGroups[info.size, default: []].append(info)
        }
        let candidateSizeGroups = sizeGroups.filter { $0.value.count > 1 }
        let candidatesForHashing = candidateSizeGroups.values.flatMap { $0 }

        progress.processedFiles = fileInfos.count

        let duplicateGroupsResult: [DuplicateGroup]
        switch scanMode {
        case .quick:
            progress.phase = "Quick scan (name + size)"
            var nameSizeGroups: [String: [FileInfo]] = [:]
            for info in candidatesForHashing {
                let key = "\(info.name)_\(info.size)"
                nameSizeGroups[key, default: []].append(info)
            }
            let quickGroups = nameSizeGroups.filter { $0.value.count > 1 }.map { (key: $0.key, files: $0.value) }
            duplicateGroupsResult = buildDuplicateGroupsQuick(from: quickGroups)
        case .smart:
            progress.phase = "Computing partial hashes"
            let partialGrouped = try await FileHashingService.partialHashFiles(
                Array(candidatesForHashing),
                using: scheduler
            )
            let partialCandidates = partialGrouped.values.filter { $0.count > 1 }.flatMap { $0 }
            try Task.checkCancellation()

            progress.phase = "Computing full SHA256"
            let fullHashGrouped = try await hashAndGroupByFullHash(files: Array(partialCandidates))
            duplicateGroupsResult = buildDuplicateGroupsWithHash(from: fullHashGrouped)
        case .deep:
            progress.phase = "Computing full SHA256 (deep scan)"
            let fullHashGrouped = try await hashAndGroupByFullHash(files: Array(candidatesForHashing))
            duplicateGroupsResult = buildDuplicateGroupsWithHash(from: fullHashGrouped)
        }

        try Task.checkCancellation()

        progress.phase = "Finding similar files"
        let duplicateFileIds = Set(duplicateGroupsResult.flatMap { $0.files.map(\.fileInfo.id) })
        let uniqueFiles = fileInfos.filter { !duplicateFileIds.contains($0.id) }
        let exactHashes = Set(duplicateGroupsResult.map(\.hash))
        similarGroups = (try? await similarFilesService.findSimilarFiles(in: uniqueFiles, exactDuplicateHashes: exactHashes)) ?? []

        return duplicateGroupsResult
    }

    private func hashAndGroupByFullHash(files: [FileInfo]) async throws -> [(hash: String, files: [FileInfo])] {
        guard !files.isEmpty else { return [] }
        let urls = files.map(\.url)
        let hashMap = try await FileHashingService.hashFiles(urls, using: scheduler)
        var grouped: [String: [FileInfo]] = [:]
        for file in files {
            guard let hash = hashMap[file.url] else { continue }
            grouped[hash, default: []].append(file)
        }
        return grouped.filter { $0.value.count > 1 }.map { (hash: $0.key, files: $0.value) }
    }

    private func applyStrategy(to files: [DuplicateFile], strategy: SmartSelectStrategy) -> [DuplicateFile] {
        switch strategy {
        case .keepOldest:
            let sorted = files.sorted { $0.fileInfo.modificationDate < $1.fileInfo.modificationDate }
            return sorted.enumerated().map { DuplicateFile(id: $1.id, fileInfo: $1.fileInfo, isSelected: $0 != 0) }
        case .keepNewest:
            let sorted = files.sorted { $0.fileInfo.modificationDate > $1.fileInfo.modificationDate }
            return sorted.enumerated().map { DuplicateFile(id: $1.id, fileInfo: $1.fileInfo, isSelected: $0 != 0) }
        case .keepShortestPath:
            let sorted = files.sorted { $0.fileInfo.relativePath.components(separatedBy: "/").count < $1.fileInfo.relativePath.components(separatedBy: "/").count }
            return sorted.enumerated().map { DuplicateFile(id: $1.id, fileInfo: $1.fileInfo, isSelected: $0 != 0) }
        case .manual:
            return files.map { DuplicateFile(id: $0.id, fileInfo: $0.fileInfo, isSelected: false) }
        }
    }

    private func buildDuplicateGroupsQuick(from groups: [(key: String, files: [FileInfo])]) -> [DuplicateGroup] {
        groups.map { item in
            let files = item.files
            let totalSize = files.reduce(0) { $0 + $1.size }
            let hash = "quick_\(item.key)"
            let duplicateFiles = files.map { DuplicateFile(id: $0.id, fileInfo: $0, isSelected: true) }
            let withStrategy = applyStrategy(to: duplicateFiles, strategy: selectStrategy)
            return DuplicateGroup(id: UUID(), hash: hash, files: withStrategy, totalSize: totalSize)
        }
    }

    private func buildDuplicateGroupsWithHash(from groups: [(hash: String, files: [FileInfo])]) -> [DuplicateGroup] {
        groups.map { item in
            let files = item.files
            let totalSize = files.reduce(0) { $0 + $1.size }
            let duplicateFiles = files.map { DuplicateFile(id: $0.id, fileInfo: $0, isSelected: true) }
            let withStrategy = applyStrategy(to: duplicateFiles, strategy: selectStrategy)
            return DuplicateGroup(id: UUID(), hash: item.hash, files: withStrategy, totalSize: totalSize)
        }
    }
}

// MARK: - Thread-safe helpers for parallel duplicate moves

private struct SendableMoveItem: @unchecked Sendable {
    let source: URL
    let dest: URL
    let hash: String
    let size: UInt64
}

private actor MoveResultCollector {
    private(set) var records: [MoveRecord] = []
    func add(_ record: MoveRecord) { records.append(record) }
}

private actor DupErrorCollector {
    private(set) var errors: [DuplicateFinderService.ScanError] = []
    func add(_ error: DuplicateFinderService.ScanError) { errors.append(error) }
}
