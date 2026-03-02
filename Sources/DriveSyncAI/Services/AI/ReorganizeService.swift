// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Combine

enum AnalysisPhase: String {
    case idle = "Ready"
    case scanning = "Scanning files..."
    case enriching = "Reading metadata..."
    case aiProcessing = "Getting AI suggestions..."
    case planReady = "Plan ready for review"
    case executing = "Executing changes..."
    case completed = "Completed"
    case failed = "Failed"
}

@MainActor
final class ReorganizeService: ObservableObject {
    @Published var phase: AnalysisPhase = .idle
    @Published var analysisProgress: Double = 0
    @Published var currentAnalysis: DriveAnalysis?
    @Published var currentPlan: ReorganizePlan?
    @Published var executionProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?

    private let safetyService: SafetyService
    private let scheduler: AdaptiveScheduler
    private let analyzer: DriveAnalyzer
    private let manifestService = ManifestService()
    private let exiftoolService = ExiftoolService()
    private var configManager: LLMConfigManager?
    private var customRulesService: CustomRulesService?

    init(safetyService: SafetyService, scheduler: AdaptiveScheduler) {
        self.safetyService = safetyService
        self.scheduler = scheduler
        self.analyzer = DriveAnalyzer(scheduler: scheduler)
    }

    func setConfigManager(_ manager: LLMConfigManager) {
        self.configManager = manager
    }

    func setCustomRulesService(_ service: CustomRulesService) {
        self.customRulesService = service
    }

    // MARK: - Analysis (Tier 1 + 2)

    func analyze(root: URL, preferences: OrganizationPreferences = .default) async {
        phase = .scanning
        errorMessage = nil
        statusMessage = "Scanning file tree..."
        analysisProgress = 0

        if preferences.generateManifests {
            statusMessage = "Generating pre-flight manifest..."
            let manifest = await manifestService.generateManifest(root: root)
            let manifestURL = root.appendingPathComponent("_reorg_manifest_before.txt")
            try? await manifestService.saveManifest(manifest, to: manifestURL)
        }

        let rules = customRulesService?.rules ?? []

        var analysis = await analyzer.analyzeTier1(root: root, customRules: rules, scope: preferences.scope)
        analysisProgress = 0.4

        phase = .enriching

        if preferences.useExiftool, await exiftoolService.isAvailable {
            statusMessage = "Enriching with exiftool batch extraction..."
            await enrichWithExiftool(analysis: &analysis, root: root)
            analysisProgress = 0.7
        }

        statusMessage = "Enriching with EXIF, PDF, and Spotlight metadata..."
        await analyzer.enrichMetadata(analysis: &analysis)
        analysisProgress = 1.0

        currentAnalysis = analysis
        statusMessage = "Analysis complete. \(analysis.totalFiles) files scanned."

        let plan = buildDeterministicPlan(from: analysis, customRules: rules, preferences: preferences)
        currentPlan = plan

        phase = .planReady
    }

    private func enrichWithExiftool(analysis: inout DriveAnalysis, root: URL) async {
        guard let results = try? await exiftoolService.extractBatch(directory: root) else { return }

        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.filePath, $0) })

        for i in analysis.categorizedFiles.indices {
            let hint = analysis.categorizedFiles[i]
            guard hint.category == .photos || hint.category == .videos else { continue }

            let fullPath = root.appendingPathComponent(hint.relativePath).path
            guard let result = resultMap[fullPath] else { continue }

            if let date = result.dateOriginal, analysis.categorizedFiles[i].exifDate == nil {
                analysis.categorizedFiles[i].exifDate = date
                analysis.categorizedFiles[i].confidence = max(analysis.categorizedFiles[i].confidence, 0.95)
            }

            if let lat = result.gpsLatitude, let lon = result.gpsLongitude,
               analysis.categorizedFiles[i].exifLocation == nil {
                analysis.categorizedFiles[i].exifLocation = String(format: "%.4f, %.4f", lat, lon)
            }
        }
    }

    // MARK: - AI Suggestions (Tier 3)

    func getAISuggestions() async {
        guard let analysis = currentAnalysis else { return }
        guard let configManager = configManager else {
            errorMessage = "AI not configured. Go to Settings to set up an LLM provider."
            return
        }

        phase = .aiProcessing
        statusMessage = "Sending summary to \(configManager.activeProvider.displayName)..."
        errorMessage = nil

        let prompt = await analyzer.generateLLMPrompt(analysis: analysis)
        let service = configManager.currentService()

        do {
            let response = try await sendWithRetry(service: service, prompt: prompt)
            let aiResponse = try LLMResponseValidator.parseOrganizeResponse(from: response)
            mergeAISuggestions(aiResponse, into: &currentPlan!, analysis: analysis)
            currentPlan?.aiModelUsed = configManager.activeModel
            statusMessage = "AI suggestions added to plan."
            phase = .planReady
        } catch {
            let retryPrompt = prompt + "\n\nIMPORTANT: Respond with ONLY valid JSON. No markdown, no explanation, no code fences."
            do {
                let response = try await service.sendPrompt(system: DriveAnalyzer.systemPrompt, user: retryPrompt)
                let aiResponse = try LLMResponseValidator.parseOrganizeResponse(from: response)
                mergeAISuggestions(aiResponse, into: &currentPlan!, analysis: analysis)
                currentPlan?.aiModelUsed = configManager.activeModel
                statusMessage = "AI suggestions added to plan (after retry)."
                phase = .planReady
            } catch {
                errorMessage = "AI failed: \(error.localizedDescription). Plan still usable with rule-based suggestions."
                phase = .planReady
            }
        }
    }

    private func sendWithRetry(service: LLMServiceProtocol, prompt: String) async throws -> String {
        return try await service.sendPrompt(system: DriveAnalyzer.systemPrompt, user: prompt)
    }

    // MARK: - Build Deterministic Plan

    private func buildDeterministicPlan(
        from analysis: DriveAnalysis,
        customRules: [CustomRule],
        preferences: OrganizationPreferences
    ) -> ReorganizePlan {
        var plan = ReorganizePlan()

        var neededFolders = Set<String>()
        var usedDestinationPaths = Set<String>()

        for file in analysis.categorizedFiles {
            guard let cat = file.category else { continue }
            if !preferences.priorityCategories.isEmpty && !preferences.priorityCategories.contains(cat) {
                continue
            }
            let destFolder = cat.suggestedFolder

            let matchedRule = customRules.first { $0.matchesFile(name: file.fileName, size: file.size, modifiedDate: file.modifiedDate, parentFolder: file.parentFolder) }

            let actualDest: String
            let source: PlanSource

            if let rule = matchedRule {
                actualDest = rule.destination
                source = .customRule
            } else {
                actualDest = destinationFolder(
                    for: file,
                    categoryFolder: destFolder,
                    preferences: preferences
                )
                source = .deterministic
            }

            neededFolders.insert(actualDest)

            let currentFolder = file.parentFolder
            if currentFolder != actualDest.components(separatedBy: "/").last {
                let destinationName = preferredFileName(for: file, preferences: preferences)
                var destinationPath = "\(actualDest)/\(destinationName)"

                if preferences.duplicatesHandling == .skipConflicts, usedDestinationPaths.contains(destinationPath) {
                    continue
                }

                if preferences.duplicatesHandling == .renameConflicts {
                    destinationPath = uniqueDestinationPath(basePath: destinationPath, usedPaths: usedDestinationPaths)
                }

                usedDestinationPaths.insert(destinationPath)

                plan.moveActions.append(MoveAction(
                    sourcePath: file.relativePath,
                    destinationPath: destinationPath,
                    fileName: file.fileName,
                    fileSize: file.size,
                    reason: "\(cat.displayName) file → \(actualDest)",
                    source: source,
                    confidence: file.confidence
                ))
            }
        }

        for folder in neededFolders.sorted() {
            let fileCount = plan.moveActions.filter { $0.destinationPath.hasPrefix(folder + "/") }.count
            if fileCount > 0 {
                plan.folderSuggestions.append(FolderSuggestion(
                    path: folder,
                    reason: "Organize \(fileCount) files",
                    fileCount: fileCount,
                    totalSize: plan.moveActions.filter { $0.destinationPath.hasPrefix(folder + "/") }.reduce(0) { $0 + $1.fileSize },
                    source: .deterministic
                ))
            }
        }

        for clutter in filteredClutterItems(analysis.clutterItems, cleanup: preferences.cleanup) {
            let action: ClutterActionType
            if preferences.cleanup.useSoftDelete {
                action = .softDelete
            } else {
                action = (clutter.reason == .emptyFolder || clutter.reason == .systemJunk) ? .delete : .archive
            }
            plan.clutterActions.append(ClutterAction(
                path: clutter.relativePath,
                action: action,
                reason: clutter.reason.displayName,
                size: clutter.size
            ))
        }

        return plan
    }

    private func destinationFolder(
        for file: FileMetadataHint,
        categoryFolder: String,
        preferences: OrganizationPreferences
    ) -> String {
        if file.category == .installers, preferences.splitInstallersByPlatform {
            let platform = file.installerPlatform ?? .other
            return "SW/\(platform.displayName)"
        }

        switch preferences.folderStructure {
        case .byType:
            if let date = file.exifDate, file.category == .photos || file.category == .videos {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                let monthName = DateFormatter().monthSymbols[month - 1]
                return "\(categoryFolder)/\(year)/\(monthName)"
            }
            return categoryFolder
        case .byDate:
            let date = file.exifDate ?? file.modifiedDate ?? Date()
            let calendar = Calendar.current
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let monthName = DateFormatter().monthSymbols[month - 1]
            return "\(year)/\(monthName)/\(categoryFolder)"
        case .byProject:
            return "\(file.parentFolder)/\(categoryFolder)"
        case .customRoot:
            let root = preferences.customRootFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeRoot = root.isEmpty ? "Organized" : root
            return "\(safeRoot)/\(categoryFolder)"
        case .photoTimeline:
            if file.category == .photos || file.category == .videos {
                return photoTimelineDestination(for: file)
            }
            return categoryFolder
        }
    }

    private func photoTimelineDestination(for file: FileMetadataHint) -> String {
        let calendar = Calendar.current
        let date = file.exifDate ?? file.modifiedDate ?? Date()
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let monthName = DateFormatter().monthSymbols[month - 1]

        var path = "Pictures/\(year)/\(monthName)"
        if let event = file.eventName, !event.isEmpty {
            let safeName = event.replacingOccurrences(of: "/", with: "-")
            path += "/\(safeName)"
        }
        return path
    }

    private func preferredFileName(for file: FileMetadataHint, preferences: OrganizationPreferences) -> String {
        let original = file.fileName
        let ext = URL(fileURLWithPath: original).pathExtension
        let stem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        switch preferences.namingConvention {
        case .original:
            return original
        case .lowercase:
            return original.lowercased()
        case .datePrefixed:
            let date = file.exifDate ?? file.modifiedDate ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let prefix = formatter.string(from: date)
            return ext.isEmpty ? "\(prefix)_\(stem)" : "\(prefix)_\(stem).\(ext)"
        case .customPrefix:
            let prefix = preferences.customNamePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return original }
            return ext.isEmpty ? "\(prefix)_\(stem)" : "\(prefix)_\(stem).\(ext)"
        }
    }

    private func uniqueDestinationPath(basePath: String, usedPaths: Set<String>) -> String {
        guard usedPaths.contains(basePath) else { return basePath }
        let url = URL(fileURLWithPath: basePath)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent().path
        var counter = 2
        while true {
            let fileName = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            let candidate = "\(folder)/\(fileName)"
            if !usedPaths.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    private func filteredClutterItems(_ items: [ClutterItem], cleanup: CleanupPreferences) -> [ClutterItem] {
        items.filter { item in
            switch item.reason {
            case .tempFile:
                return cleanup.includeTempFiles
            case .systemJunk:
                return cleanup.includeSystemJunk
            case .emptyFolder:
                return cleanup.includeEmptyFolders
            default:
                return true
            }
        }
    }

    // MARK: - Merge AI Suggestions

    private func mergeAISuggestions(_ aiResponse: AIOrganizeResponse, into plan: inout ReorganizePlan, analysis: DriveAnalysis) {
        if let folders = aiResponse.folderStructure {
            for folder in folders {
                if !plan.folderSuggestions.contains(where: { $0.path == folder.path }) {
                    plan.folderSuggestions.append(FolderSuggestion(
                        path: folder.path,
                        reason: folder.reason,
                        fileCount: 0,
                        totalSize: 0,
                        source: .ai
                    ))
                }
            }
        }

        if let classifications = aiResponse.fileClassifications {
            for classification in classifications {
                if let match = analysis.ambiguousFiles.first(where: { $0.fileName == classification.file }) {
                    let dest = classification.suggestedPath ?? "\(classification.category)/\(classification.file)"
                    plan.moveActions.append(MoveAction(
                        sourcePath: match.relativePath,
                        destinationPath: dest,
                        fileName: match.fileName,
                        fileSize: match.size,
                        reason: "AI classified as \(classification.category)",
                        source: .ai,
                        confidence: classification.confidence ?? 0.7
                    ))
                }
            }
        }

        if let renames = aiResponse.renameSuggestions {
            for rename in renames {
                plan.renameSuggestions.append(RenameSuggestion(
                    filePath: rename.from,
                    originalName: URL(fileURLWithPath: rename.from).lastPathComponent,
                    suggestedName: rename.to,
                    reason: rename.reason
                ))
            }
        }

        if let clutters = aiResponse.clutterActions {
            for clutter in clutters {
                if !plan.clutterActions.contains(where: { $0.path == clutter.path }) {
                    let actionType: ClutterActionType = clutter.action == "delete" ? .delete : .archive
                    plan.clutterActions.append(ClutterAction(
                        path: clutter.path,
                        action: actionType,
                        reason: clutter.reason,
                        size: 0
                    ))
                }
            }
        }
    }

    // MARK: - Execute Plan

    func executePlan(dryRun: Bool = false) async {
        guard let plan = currentPlan, let analysis = currentAnalysis else { return }
        let root = analysis.rootPath
        let fm = FileManager.default

        phase = .executing
        executionProgress = 0
        statusMessage = dryRun ? "Dry run: previewing changes..." : "Executing plan..."

        let acceptedMoves = plan.moveActions.filter(\.accepted)
        let acceptedRenames = plan.renameSuggestions.filter(\.accepted)
        let acceptedClutter = plan.clutterActions.filter(\.accepted)
        let totalActions = acceptedMoves.count + acceptedRenames.count + acceptedClutter.count
        var completed = 0

        guard let jobId = try? await safetyService.startJob() else {
            errorMessage = "Failed to begin safety journal"
            phase = .failed
            return
        }

        if !dryRun {
            var createdDirs = Set<String>()
            for folder in plan.folderSuggestions.filter(\.accepted) {
                let dirURL = root.appendingPathComponent(folder.path)
                if !createdDirs.contains(folder.path) {
                    try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    createdDirs.insert(folder.path)
                }
            }

            for move in acceptedMoves {
                let sourceURL = root.appendingPathComponent(move.sourcePath)
                let destURL = root.appendingPathComponent(move.destinationPath)

                do {
                    try await safetyService.recordMove(jobId: jobId, source: sourceURL, destination: destURL)
                } catch {
                    // Error already journaled by SafetyService
                }

                completed += 1
                executionProgress = Double(completed) / Double(totalActions)
                statusMessage = "Moving files... (\(completed)/\(totalActions))"
            }

            for rename in acceptedRenames {
                let fileURL = root.appendingPathComponent(rename.filePath)
                let destURL = fileURL.deletingLastPathComponent().appendingPathComponent(rename.suggestedName)

                do {
                    try await safetyService.recordMove(jobId: jobId, source: fileURL, destination: destURL)
                } catch {
                    // Error already journaled by SafetyService
                }

                completed += 1
                executionProgress = Double(completed) / Double(totalActions)
                statusMessage = "Renaming files... (\(completed)/\(totalActions))"
            }

            for clutter in acceptedClutter {
                let clutterURL = root.appendingPathComponent(clutter.path)

                do {
                    switch clutter.action {
                    case .delete:
                        try await safetyService.recordDelete(jobId: jobId, target: clutterURL)
                    case .softDelete:
                        let deletedURL = root.appendingPathComponent("_Deleted").appendingPathComponent(clutter.path)
                        try fm.createDirectory(at: deletedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try await safetyService.recordMove(jobId: jobId, source: clutterURL, destination: deletedURL)
                    case .archive:
                        let archiveURL = root.appendingPathComponent("Archive").appendingPathComponent(clutter.path)
                        try await safetyService.recordMove(jobId: jobId, source: clutterURL, destination: archiveURL)
                    case .ignore:
                        break
                    }
                } catch {
                    // Error already journaled by SafetyService
                }

                completed += 1
                executionProgress = Double(completed) / Double(totalActions)
                statusMessage = "Cleaning up... (\(completed)/\(totalActions))"
            }

            let emptiedFolders = detectEmptiedSourceFolders(plan: plan, root: root)
            if !emptiedFolders.isEmpty {
                statusMessage = "Moving emptied source folders to _Sorted_Originals/..."
                for folderPath in emptiedFolders {
                    let sourceURL = root.appendingPathComponent(folderPath)
                    let holdingURL = root.appendingPathComponent("_Sorted_Originals").appendingPathComponent(folderPath)
                    do {
                        try fm.createDirectory(at: holdingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try await safetyService.recordMove(jobId: jobId, source: sourceURL, destination: holdingURL)
                    } catch {
                        // Folder may already be gone or non-empty
                    }
                }
                currentPlan?.emptiedSourceFolders = emptiedFolders
            }
        }

        try? await safetyService.completeJob(jobId)

        if !dryRun {
            statusMessage = "Generating post-flight manifest..."
            let postManifest = await manifestService.generateManifest(root: root)
            let postManifestURL = root.appendingPathComponent("_reorg_manifest_after.txt")
            try? await manifestService.saveManifest(postManifest, to: postManifestURL)

            let preManifestURL = root.appendingPathComponent("_reorg_manifest_before.txt")
            if let preEntries = try? await manifestService.loadManifest(from: preManifestURL) {
                let comparison = await manifestService.compare(before: preEntries, after: postManifest)
                if comparison.isConsistent {
                    statusMessage = "Reorganization complete! \(completed) actions executed. All files verified."
                } else {
                    statusMessage = "Reorganization complete! \(completed) actions executed. \(comparison.summary)"
                }
            } else {
                statusMessage = "Reorganization complete! \(completed) actions executed."
            }
        } else {
            statusMessage = "Dry run complete."
        }

        executionProgress = 1.0
        phase = .completed
    }

    private func detectEmptiedSourceFolders(plan: ReorganizePlan, root: URL) -> [String] {
        let fm = FileManager.default
        var sourceFolders = Set<String>()
        for move in plan.moveActions.filter(\.accepted) {
            let parentPath = (move.sourcePath as NSString).deletingLastPathComponent
            if !parentPath.isEmpty {
                sourceFolders.insert(parentPath)
            }
        }

        var emptied: [String] = []
        for folder in sourceFolders.sorted() {
            let folderURL = root.appendingPathComponent(folder)
            guard let contents = try? fm.contentsOfDirectory(atPath: folderURL.path) else { continue }
            let remaining = contents.filter { !$0.hasPrefix(".") }
            if remaining.isEmpty {
                emptied.append(folder)
            }
        }
        return emptied
    }

    // MARK: - Reset

    func reset() {
        phase = .idle
        analysisProgress = 0
        currentAnalysis = nil
        currentPlan = nil
        executionProgress = 0
        statusMessage = ""
        errorMessage = nil
    }
}
