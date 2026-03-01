// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Combine

@MainActor
final class SyncService: ObservableObject {
    @Published var sourceURL: URL?
    @Published var targetURL: URL?
    @Published var direction: SyncDirection = .oneWayUpdate
    @Published var conflictStrategy: ConflictResolutionStrategy = .keepBoth
    @Published var versioningStrategy: VersioningStrategy = .disabled
    @Published var filterRules: [FilterRule] = FilterRule.defaultExcludes
    @Published var parallelIOEnabled: Bool = false

    @Published var state: SyncState = .idle
    @Published var actions: [SyncAction] = []
    @Published var currentItem: SyncItem?
    @Published var progress: SyncProgress = .init()
    @Published var errors: [SyncError] = []

    enum SyncState {
        case idle
        case comparing
        case previewing
        case syncing
        case paused
        case completed
        case failed
    }

    struct SyncProgress {
        var totalFiles: Int = 0
        var completedFiles: Int = 0
        var totalBytes: UInt64 = 0
        var transferredBytes: UInt64 = 0
        var currentFileName: String = ""
        var speed: Double = 0
        var eta: TimeInterval = 0

        var percentage: Double {
            guard totalFiles > 0 else { return 0 }
            return min(1, Double(completedFiles) / Double(totalFiles)) * 100
        }

        var bytesPercentage: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, Double(transferredBytes) / Double(totalBytes)) * 100
        }
    }

    struct SyncError: Identifiable {
        let id: UUID
        let filePath: String
        let message: String
        let timestamp: Date

        init(filePath: String, message: String) {
            self.id = UUID()
            self.filePath = filePath
            self.message = message
            self.timestamp = Date()
        }
    }

    private let safetyService: SafetyService
    private let scheduler: AdaptiveScheduler
    private weak var achievementService: AchievementService?
    private let compareEngine: CompareEngine
    private var currentJobId: UUID?
    private var syncTask: Task<Void, Never>?
    private var isPaused = false
    private var isCancelled = false
    private var sourceDriveInfo: DriveInfo?
    private var targetDriveInfo: DriveInfo?
    private var progressUpdateTask: Task<Void, Never>?

    init(safetyService: SafetyService, scheduler: AdaptiveScheduler, achievementService: AchievementService? = nil) {
        self.safetyService = safetyService
        self.scheduler = scheduler
        self.achievementService = achievementService
        self.compareEngine = CompareEngine(scheduler: scheduler, safetyService: safetyService)
    }

    func setDriveInfo(source: DriveInfo?, target: DriveInfo?) {
        sourceDriveInfo = source
        targetDriveInfo = target
    }

    /// Step 1: Compare source and target, populate actions for preview
    func compare() async {
        guard let source = sourceURL, let target = targetURL else {
            state = .failed
            return
        }

        state = .comparing
        errors = []
        progress = .init()
        currentItem = nil

        let srcDrive = sourceDriveInfo ?? DriveInfo(id: UUID(), url: source, name: source.lastPathComponent, totalCapacity: 0, availableCapacity: 0, connectionType: .unknown, isRemovable: false, volumeFormat: "APFS", isCaseSensitive: false)
        let tgtDrive = targetDriveInfo ?? DriveInfo(id: UUID(), url: target, name: target.lastPathComponent, totalCapacity: 0, availableCapacity: 0, connectionType: .unknown, isRemovable: false, volumeFormat: "APFS", isCaseSensitive: false)

        await scheduler.updateIOLimit(for: [srcDrive, tgtDrive])

        do {
            let result = try await compareEngine.compare(
                source: source,
                target: target,
                direction: direction,
                sourceDriveInfo: srcDrive,
                targetDriveInfo: tgtDrive,
                filterRules: filterRules
            )

            actions = result
            state = .previewing
            progress = SyncProgress(totalFiles: result.count)
        } catch {
            state = .failed
            errors.append(SyncError(filePath: "", message: error.localizedDescription))
        }
    }

    /// Step 2: Execute selected actions
    func startSync() async {
        guard let source = sourceURL, let target = targetURL else {
            state = .failed
            return
        }

        let selectedActions = actions.filter { $0.isSelected }
        guard !selectedActions.isEmpty else {
            state = .completed
            return
        }

        var actionsToExecute: [SyncAction] = []
        for action in selectedActions {
            if action.actionType == .conflict {
                let resolved = ConflictResolver.resolve(
                    conflict: action,
                    strategy: conflictStrategy,
                    sourceRoot: source,
                    targetRoot: target
                )
                actionsToExecute.append(contentsOf: resolved)
            } else {
                actionsToExecute.append(action)
            }
        }

        let filtered = actionsToExecute.filter { $0.isSelected }
        guard !filtered.isEmpty else {
            state = .completed
            return
        }

        isPaused = false
        isCancelled = false
        state = .syncing
        errors = []
        let totalBytes = filtered.reduce(UInt64(0)) { $0 + $1.fileSize }
        progress = SyncProgress(totalFiles: filtered.count, totalBytes: totalBytes)

        do {
            currentJobId = try await safetyService.startJob()
        } catch {
            state = .failed
            errors.append(SyncError(filePath: "", message: error.localizedDescription))
            return
        }

        syncTask = Task { [weak self] in
            await self?.executeActions(actions: filtered, source: source, target: target)
        }

        progressUpdateTask = Task { [weak self] in
            await self?.runProgressUpdates()
        }

        await syncTask?.value
        progressUpdateTask?.cancel()
        progressUpdateTask = nil

        if let jobId = currentJobId {
            try? await safetyService.completeJob(jobId)
        }
        currentJobId = nil

        if isCancelled {
            state = .failed
        } else {
            state = .completed
            achievementService?.recordSync(fileCount: progress.completedFiles, byteCount: progress.transferredBytes)
        }
    }

    private func executeActions(actions: [SyncAction], source: URL, target: URL) async {
        guard let jobId = currentJobId else { return }

        if parallelIOEnabled {
            await executeActionsParallel(actions: actions, source: source, target: target, jobId: jobId)
        } else {
            await executeActionsSequential(actions: actions, source: source, target: target, jobId: jobId)
        }
    }

    private func executeActionsSequential(actions: [SyncAction], source: URL, target: URL, jobId: UUID) async {
        var completedCount = 0
        var transferredBytes: UInt64 = 0
        var bidirectionalFiles: [String: (sourceMod: Date?, targetMod: Date?)] = [:]

        for action in actions {
            do { try Task.checkCancellation() } catch { isCancelled = true; break }
            if isCancelled { break }
            while isPaused { try? await Task.sleep(nanoseconds: 100_000_000) }

            let item = SyncItem(id: action.id, action: action, status: .inProgress, bytesTransferred: 0, errorMessage: nil)
            await MainActor.run { currentItem = item }

            do {
                try await executeSingleAction(action: action, source: source, target: target, jobId: jobId)
            } catch {
                await MainActor.run {
                    errors.append(SyncError(filePath: action.relativePath, message: error.localizedDescription))
                    currentItem = SyncItem(id: action.id, action: action, status: .failed, bytesTransferred: 0, errorMessage: error.localizedDescription)
                }
            }

            let size = action.fileSize
            if action.actionType != .skip && action.actionType != .conflict {
                transferredBytes += size
                if direction == .bidirectional, let src = action.sourceFile, let tgt = action.targetFile {
                    bidirectionalFiles[action.relativePath] = (src.modificationDate, tgt.modificationDate)
                }
            }

            completedCount += 1
            await MainActor.run {
                progress.completedFiles = completedCount
                progress.transferredBytes = transferredBytes
                progress.currentFileName = action.displayName
                currentItem = SyncItem(id: action.id, action: action, status: .completed, bytesTransferred: size, errorMessage: nil)
            }
        }

        if direction == .bidirectional && !bidirectionalFiles.isEmpty {
            await compareEngine.saveSyncState(source: source, target: target, files: bidirectionalFiles)
        }
    }

    private func executeActionsParallel(actions: [SyncAction], source: URL, target: URL, jobId: UUID) async {
        let completedCount = CompletedCounter()
        let transferredCounter = TransferredCounter()
        let bidirectionalCollector = BidirectionalCollector()
        let errorCollector = ErrorCollector()

        let actionItems = actions.map { SendableSyncAction(action: $0) }
        let src = source
        let tgt = target
        let dir = direction
        let sched = scheduler

        do {
            _ = try await sched.runParallelIO(items: actionItems) { [weak self] item in
                let action = item.action
                guard let self else { return }

                do {
                    try await self.executeSingleAction(action: action, source: src, target: tgt, jobId: jobId)
                } catch {
                    await errorCollector.add(SyncError(filePath: action.relativePath, message: error.localizedDescription))
                }

                let size = action.fileSize
                if action.actionType != .skip && action.actionType != .conflict {
                    await transferredCounter.add(size)
                    if dir == .bidirectional, let srcFile = action.sourceFile, let tgtFile = action.targetFile {
                        await bidirectionalCollector.add(path: action.relativePath, sourceMod: srcFile.modificationDate, targetMod: tgtFile.modificationDate)
                    }
                }

                let count = await completedCount.increment()
                let transferred = await transferredCounter.total
                await MainActor.run {
                    self.progress.completedFiles = count
                    self.progress.transferredBytes = transferred
                    self.progress.currentFileName = action.displayName
                }
            }
        } catch {
            await MainActor.run {
                errors.append(SyncError(filePath: "", message: error.localizedDescription))
            }
        }

        let collectedErrors = await errorCollector.errors
        if !collectedErrors.isEmpty {
            await MainActor.run {
                errors.append(contentsOf: collectedErrors)
            }
        }

        let biFiles = await bidirectionalCollector.files
        if direction == .bidirectional && !biFiles.isEmpty {
            await compareEngine.saveSyncState(source: source, target: target, files: biFiles)
        }
    }

    private nonisolated func executeSingleAction(action: SyncAction, source: URL, target: URL, jobId: UUID) async throws {
        switch action.actionType {
        case .create:
            try await executeCreate(action: action, source: source, target: target, jobId: jobId)
        case .update:
            try await executeUpdate(action: action, source: source, target: target, jobId: jobId)
        case .delete:
            try await executeDelete(action: action, target: target, jobId: jobId)
        case .skip, .conflict:
            break
        }
    }

    private func executeCreate(action: SyncAction, source: URL, target: URL, jobId: UUID) async throws {
        guard let srcFile = action.sourceFile else { return }
        let srcURL = srcFile.url
        let destURL = target.appendingPathComponent(action.relativePath)
        let srcRoot = srcFile.driveRoot

        if srcRoot.standardized.path == source.standardized.path {
            try await safetyService.recordCopy(jobId: jobId, source: srcURL, destination: destURL, sourceHash: nil)
        } else {
            try await safetyService.recordCopy(jobId: jobId, source: srcURL, destination: source.appendingPathComponent(action.relativePath), sourceHash: nil)
        }
    }

    private func executeUpdate(action: SyncAction, source: URL, target: URL, jobId: UUID) async throws {
        guard let srcFile = action.sourceFile, action.targetFile != nil else { return }
        let srcURL = srcFile.url
        let srcRoot = srcFile.driveRoot

        let destURL: URL
        if srcRoot.standardized.path == source.standardized.path {
            destURL = target.appendingPathComponent(action.relativePath)
        } else {
            destURL = source.appendingPathComponent(action.relativePath)
        }

        if FileManager.default.fileExists(atPath: destURL.path) {
            if versioningStrategy != .disabled {
                let versionsRoot = destURL.path.hasPrefix(target.standardized.path) ? target : source
                let versionsDir = versionsRoot.appendingPathComponent(".versions", isDirectory: true)
                let versioningService = VersioningService(strategy: versioningStrategy, versionsDirectory: versionsDir)
                _ = try await versioningService.backupBeforeOverwrite(file: destURL)
            }
            try await safetyService.recordOverwrite(jobId: jobId, source: srcURL, destination: destURL, sourceHash: nil, destHash: nil)
        } else {
            try await safetyService.recordCopy(jobId: jobId, source: srcURL, destination: destURL, sourceHash: nil)
        }
    }

    private func executeDelete(action: SyncAction, target: URL, jobId: UUID) async throws {
        guard action.targetFile != nil else { return }
        let tgtURL = target.appendingPathComponent(action.relativePath)
        if versioningStrategy != .disabled {
            let versionsDir = target.appendingPathComponent(".versions", isDirectory: true)
            let versioningService = VersioningService(strategy: versioningStrategy, versionsDirectory: versionsDir)
            _ = try await versioningService.backupBeforeOverwrite(file: tgtURL)
        }
        try await safetyService.recordDelete(jobId: jobId, target: tgtURL)
    }

    private nonisolated func runProgressUpdates() async {
        var lastBytes: UInt64 = 0
        var lastTime = Date()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let (currentBytes, totalBytes) = await MainActor.run { (progress.transferredBytes, progress.totalBytes) }
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTime)
            guard elapsed > 0 else { continue }
            let delta = currentBytes > lastBytes ? currentBytes - lastBytes : 0
            let speed = Double(delta) / elapsed
            lastBytes = currentBytes
            lastTime = now
            let remaining = totalBytes > currentBytes ? totalBytes - currentBytes : 0
            let eta: TimeInterval = speed > 0 ? Double(remaining) / speed : 0
            await MainActor.run {
                progress.speed = speed
                progress.eta = eta
            }
        }
    }

    func pause() {
        isPaused = true
        state = .paused
    }

    func resume() async {
        isPaused = false
        state = .syncing
    }

    func cancel() {
        isCancelled = true
        syncTask?.cancel()
        state = .failed
    }

    func toggleAction(_ id: UUID) {
        guard let idx = actions.firstIndex(where: { $0.id == id }) else { return }
        var updated = actions
        updated[idx].isSelected.toggle()
        actions = updated
    }

    func selectAll(_ selected: Bool) {
        actions = actions.map { var a = $0; a.isSelected = selected; return a }
    }

    /// Resolve a single conflict action with a strategy; replaces it in the actions array
    func resolveConflict(actionId: UUID, strategy: ConflictResolutionStrategy) {
        guard let source = sourceURL, let target = targetURL,
              let idx = actions.firstIndex(where: { $0.id == actionId }),
              actions[idx].actionType == .conflict else { return }

        let conflict = actions[idx]
        let resolved = ConflictResolver.resolve(
            conflict: conflict,
            strategy: strategy,
            sourceRoot: source,
            targetRoot: target
        )
        var updated = actions
        updated.remove(at: idx)
        updated.insert(contentsOf: resolved, at: idx)
        actions = updated
    }
}

// MARK: - Thread-safe counters for parallel execution

private actor CompletedCounter {
    private var count = 0
    func increment() -> Int { count += 1; return count }
}

private actor TransferredCounter {
    private(set) var total: UInt64 = 0
    func add(_ bytes: UInt64) { total += bytes }
}

private actor BidirectionalCollector {
    private(set) var files: [String: (sourceMod: Date?, targetMod: Date?)] = [:]
    func add(path: String, sourceMod: Date?, targetMod: Date?) {
        files[path] = (sourceMod, targetMod)
    }
}

private actor ErrorCollector {
    private(set) var errors: [SyncService.SyncError] = []
    func add(_ error: SyncService.SyncError) { errors.append(error) }
}

private struct SendableSyncAction: @unchecked Sendable {
    let action: SyncAction
}
