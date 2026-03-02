// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct OrganizationChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String // "user", "assistant", "system"
    let text: String
    let isStatusMessage: Bool

    init(role: String, text: String, isStatusMessage: Bool = false) {
        self.role = role
        self.text = text
        self.isStatusMessage = isStatusMessage
    }
}

@MainActor
final class OrganizationChatService: ObservableObject {
    @Published var messages: [OrganizationChatMessage] = []
    @Published var ruleCandidates: [RuleCandidate] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastAppliedChangesCount: Int = 0

    private var conversationHistory: [(role: String, content: String)] = []

    func clear() {
        messages = []
        ruleCandidates = []
        conversationHistory = []
        isLoading = false
        lastError = nil
        lastAppliedChangesCount = 0
    }

    // MARK: - Pre-Scan Chat (preferences only)

    @discardableResult
    func send(
        userText: String,
        preferences: OrganizationPreferences,
        configManager: LLMConfigManager
    ) async -> RefinementResult {
        return await sendMessage(
            userText: userText,
            preferences: preferences,
            analysis: nil,
            plan: nil,
            configManager: configManager
        )
    }

    // MARK: - Post-Scan Chat (preferences + analysis + plan)

    func send(
        userText: String,
        preferences: OrganizationPreferences,
        analysis: DriveAnalysis?,
        plan: ReorganizePlan?,
        configManager: LLMConfigManager
    ) async -> RefinementResult {
        return await sendMessage(
            userText: userText,
            preferences: preferences,
            analysis: analysis,
            plan: plan,
            configManager: configManager
        )
    }

    func addWelcomeMessage(analysis: DriveAnalysis?, plan: ReorganizePlan?) {
        if messages.contains(where: { $0.isStatusMessage && $0.role == "assistant" }) { return }
        let fileCount = analysis?.totalFiles ?? 0
        let moveCount = plan?.moveActions.count ?? 0
        let msg = "I can see your organization plan — \(fileCount) files scanned, \(moveCount) moves planned. " +
            "Tell me what you'd like to change. For example:\n" +
            "• \"Move all PDFs to a Reports folder\"\n" +
            "• \"Don't touch anything in Downloads\"\n" +
            "• \"Group photos by month instead of type\""
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    // MARK: - Local Commands

    private static let showPlanAliases: Set<String> = [
        "show plan", "show the plan", "view plan", "display plan",
        "what's the plan", "whats the plan", "plan summary", "show summary"
    ]

    private static let categoryQueryPrefixes = [
        "show photos", "show videos", "show documents", "show installers",
        "show music", "show archives", "show cleanup", "show moves for"
    ]

    private func tryLocalCommand(
        _ text: String,
        plan: ReorganizePlan?,
        analysis: DriveAnalysis?
    ) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if Self.showPlanAliases.contains(lower), let plan = plan {
            return formatPlanSummary(plan)
        }

        if let plan = plan {
            for prefix in Self.categoryQueryPrefixes {
                if lower.hasPrefix(prefix) {
                    let category = lower.replacingOccurrences(of: prefix, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return formatCategoryMoves(plan: plan, query: category.isEmpty ? prefix : category)
                }
            }
        }

        return nil
    }

    private func formatPlanSummary(_ plan: ReorganizePlan) -> String {
        var lines: [String] = []
        lines.append("📋 **Plan Summary**")
        lines.append("")
        lines.append("• \(plan.totalAcceptedMoves) file moves accepted")
        lines.append("• \(plan.totalAcceptedRenames) renames accepted")
        lines.append("• \(plan.totalAcceptedClutter) cleanup items")

        if plan.estimatedSpaceSaved > 0 {
            lines.append("• Estimated space saved: \(ByteCountFormatter.string(fromByteCount: plan.estimatedSpaceSaved, countStyle: .file))")
        }

        let softDeleteCount = plan.clutterActions.filter { $0.accepted && $0.action == .softDelete }.count
        if softDeleteCount > 0 {
            lines.append("• \(softDeleteCount) items will be soft-deleted to _Deleted/")
        }

        lines.append("")

        let grouped = Dictionary(grouping: plan.moveActions.filter(\.accepted)) { move -> String in
            move.destinationPath.components(separatedBy: "/").first ?? "Other"
        }
        if !grouped.isEmpty {
            lines.append("**Destination folders:**")
            for (folder, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
                let size = items.reduce(Int64(0)) { $0 + $1.fileSize }
                lines.append("  📁 \(folder): \(items.count) files (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
            }
        }

        lines.append("")
        lines.append("Use the **Overview** tab in the plan view for the full folder tree, or tap **Export Plan** to save a text file.")

        return lines.joined(separator: "\n")
    }

    private func formatCategoryMoves(plan: ReorganizePlan, query: String) -> String {
        let lower = query.lowercased()
        let matchingMoves = plan.moveActions.filter { move in
            move.accepted && (
                move.reason.lowercased().contains(lower) ||
                move.destinationPath.lowercased().contains(lower)
            )
        }

        if matchingMoves.isEmpty {
            return "No matching moves found for \"\(query)\" in the current plan."
        }

        var lines: [String] = []
        lines.append("Found \(matchingMoves.count) moves matching \"\(query)\":")
        for move in matchingMoves.prefix(20) {
            lines.append("  \(move.fileName) → \(move.destinationPath)")
        }
        if matchingMoves.count > 20 {
            lines.append("  ... and \(matchingMoves.count - 20) more")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Core Send

    @discardableResult
    private func sendMessage(
        userText: String,
        preferences: OrganizationPreferences,
        analysis: DriveAnalysis?,
        plan: ReorganizePlan?,
        configManager: LLMConfigManager
    ) async -> RefinementResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        messages.append(OrganizationChatMessage(role: "user", text: trimmed))
        conversationHistory.append((role: "user", content: trimmed))

        if let localResponse = tryLocalCommand(trimmed, plan: plan, analysis: analysis) {
            messages.append(OrganizationChatMessage(role: "assistant", text: localResponse))
            conversationHistory.append((role: "assistant", content: localResponse))
            return .empty
        }

        isLoading = true
        lastError = nil
        lastAppliedChangesCount = 0

        let service = configManager.currentService()
        let systemPrompt = buildSystemPrompt(analysis: analysis, plan: plan)
        let userPrompt = buildUserPrompt(
            text: trimmed,
            preferences: preferences,
            analysis: analysis,
            plan: plan
        )

        do {
            let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
            guard let json = LLMResponseValidator.extractJSON(from: response),
                  let data = json.data(using: .utf8) else {
                throw LLMError.invalidJSON("Could not extract JSON from response")
            }

            let decoded: OrganizationRefinementResponse
            do {
                decoded = try JSONDecoder().decode(OrganizationRefinementResponse.self, from: data)
            } catch let decodeError {
                throw LLMError.invalidJSON("Decode failed: \(decodeError.localizedDescription)")
            }

            var assistantText = [decoded.assistantMessage, decoded.followUpQuestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")

            if assistantText.isEmpty {
                let hasMods = !(decoded.planModifications ?? []).isEmpty
                let hasPrefs = !(decoded.preferenceChanges ?? []).isEmpty
                if hasMods || hasPrefs || (decoded.shouldReAnalyze ?? false) {
                    assistantText = "Got it — updating your plan now."
                }
            }

            if !assistantText.isEmpty {
                messages.append(OrganizationChatMessage(role: "assistant", text: assistantText))
                conversationHistory.append((role: "assistant", content: assistantText))
            }

            if let candidates = decoded.ruleCandidates, !candidates.isEmpty {
                ruleCandidates = candidates.map { candidate in
                    RuleCandidate(
                        id: UUID(),
                        name: candidate.name,
                        pattern: candidate.pattern,
                        destination: candidate.destination,
                        selectedForSave: true
                    )
                }
            }

            isLoading = false

            return RefinementResult(
                planModifications: decoded.planModifications,
                preferenceChanges: decoded.preferenceChanges,
                shouldReAnalyze: decoded.shouldReAnalyze ?? false
            )
        } catch {
            lastError = error.localizedDescription
            messages.append(
                OrganizationChatMessage(
                    role: "assistant",
                    text: "Sorry, I couldn't process that. Could you rephrase what you'd like to change?"
                )
            )
            conversationHistory.append((role: "assistant", content: "Error processing request."))
            isLoading = false
            return .empty
        }
    }

    // MARK: - System Prompts

    private func buildSystemPrompt(analysis: DriveAnalysis?, plan: ReorganizePlan?) -> String {
        let hasContext = analysis != nil || plan != nil
        if hasContext {
            return postScanSystemPrompt
        }
        return preScanSystemPrompt
    }

    private var preScanSystemPrompt: String {
        """
        You are an interactive file-organization assistant for a macOS app called DriveSyncAI.
        Your job is to help the user configure how they want their files organized.

        CONVERSATION RULES:
        - Ask follow-up questions when the user's intent is unclear or too vague.
        - Be concise — 2-3 sentences max per response unless explaining something complex.
        - If the user says something ambiguous like "organize my files", ask what kind of files and how they want them grouped.
        - Suggest concrete preference changes or custom rules based on what you learn.

        RESPONSE FORMAT (JSON only, no markdown):
        {
          "assistantMessage": "Your response to the user",
          "followUpQuestion": "A clarifying question if needed, or null",
          "ruleCandidates": [{"name":"rule name","pattern":"glob pattern","destination":"target folder"}],
          "preferenceChanges": [{"field":"folderStructure","value":"byDate"}],
          "shouldReAnalyze": false
        }

        Valid preference fields: folderStructure (byType/byDate/byProject/customRoot/photoTimeline), namingConvention (original/lowercase/datePrefixed/customPrefix), duplicatesHandling (skipConflicts/renameConflicts/replaceExisting), scope (fullRecursive/topLevelOnly/maxDepth3), splitInstallersByPlatform (true/false), useSoftDelete (true/false).
        """
    }

    private var postScanSystemPrompt: String {
        """
        You are an interactive file-organization assistant for DriveSyncAI. The user has already scanned their drive and has an organization plan. You can SEE the current plan and file data.

        CONVERSATION RULES:
        - Ask follow-up questions when the user's intent is unclear.
        - Be concise — 2-3 sentences max.
        - When modifying the plan, explain what you changed and why.
        - If a request would affect many files, confirm with the user first.
        - If the user's request needs fundamentally different organization (e.g. switching from by-type to by-date), set shouldReAnalyze to true.

        PLAN MODIFICATION ACTIONS:
        - "addMove": Add a new file move (requires fileName, destinationPath)
        - "removeMove": Exclude a file from the plan (requires fileName)
        - "changeDestination": Move a file to a different folder (requires fileName, destinationPath)
        - "addCleanup": Mark a file for cleanup (requires fileName, reason)
        - "removeCleanup": Exclude a file from cleanup (requires fileName)
        - "addRename": Suggest renaming a file (requires fileName, destinationPath as new name, reason)

        RESPONSE FORMAT (JSON only, no markdown):
        {
          "assistantMessage": "Your response explaining what you did or asking for clarification",
          "followUpQuestion": "A clarifying question if needed, or null",
          "planModifications": [{"action":"changeDestination","fileName":"report.pdf","destinationPath":"Reports/2024/","reason":"User requested"}],
          "preferenceChanges": [{"field":"folderStructure","value":"byDate"}],
          "shouldReAnalyze": false,
          "ruleCandidates": []
        }
        """
    }

    // MARK: - User Prompt Construction

    private func buildUserPrompt(
        text: String,
        preferences: OrganizationPreferences,
        analysis: DriveAnalysis?,
        plan: ReorganizePlan?
    ) -> String {
        var parts: [String] = []

        // Conversation history for multi-turn context
        if conversationHistory.count > 1 {
            let recentHistory = conversationHistory.suffix(10)
            let historyText = recentHistory.dropLast().map { turn in
                "\(turn.role): \(turn.content)"
            }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        // Current preferences
        parts.append("""
        CURRENT PREFERENCES:
        - folderStructure: \(preferences.folderStructure.rawValue)
        - namingConvention: \(preferences.namingConvention.rawValue)
        - duplicatesHandling: \(preferences.duplicatesHandling.rawValue)
        - scope: \(preferences.scope.rawValue)
        - priorityCategories: \(preferences.priorityCategories.isEmpty ? "all" : preferences.priorityCategories.map(\.rawValue).sorted().joined(separator: ", "))
        """)

        // Analysis context (post-scan)
        if let analysis = analysis {
            let catSummary = analysis.categories
                .sorted { $0.value.fileCount > $1.value.fileCount }
                .map { "\($0.key.displayName): \($0.value.fileCount) files (\(ByteCountFormatter.string(fromByteCount: $0.value.totalSize, countStyle: .file)))" }
                .joined(separator: "\n  ")
            parts.append("""
            SCAN RESULTS:
            - Total files: \(analysis.totalFiles)
            - Total size: \(ByteCountFormatter.string(fromByteCount: analysis.totalSize, countStyle: .file))
            - Ambiguous files: \(analysis.ambiguousFiles.count)
            - Categories:
              \(catSummary)
            """)
        }

        // Plan context (post-scan)
        if let plan = plan {
            let topMoves = plan.moveActions.prefix(30).map { move in
                "  \(move.fileName): \(move.sourcePath) → \(move.destinationPath) [\(move.source.displayName)]"
            }.joined(separator: "\n")

            let topCleanup = plan.clutterActions.prefix(10).map { item in
                "  \(item.path) (\(item.action.displayName)): \(item.reason)"
            }.joined(separator: "\n")

            parts.append("""
            CURRENT PLAN:
            - Moves: \(plan.moveActions.count) (\(plan.totalAcceptedMoves) accepted)
            - Renames: \(plan.renameSuggestions.count)
            - Cleanup: \(plan.clutterActions.count)
            \(topMoves.isEmpty ? "" : "TOP MOVES:\n\(topMoves)")
            \(topCleanup.isEmpty ? "" : "CLEANUP ITEMS:\n\(topCleanup)")
            """)
        }

        parts.append("USER MESSAGE:\n\(text)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Plan Mutation

    static func applyPlanModifications(
        _ modifications: [PlanModification],
        to plan: inout ReorganizePlan
    ) -> [String] {
        var changeDescriptions: [String] = []

        for mod in modifications {
            guard PlanModification.validActions.contains(mod.action) else { continue }

            switch mod.action {
            case "addMove":
                guard let fileName = mod.fileName, let dest = mod.destinationPath else { continue }
                let newMove = MoveAction(
                    sourcePath: mod.sourcePath ?? "",
                    destinationPath: dest,
                    fileName: fileName,
                    fileSize: 0,
                    reason: mod.reason ?? "Added by AI chat",
                    source: .ai,
                    confidence: 0.9,
                    accepted: true
                )
                plan.moveActions.append(newMove)
                changeDescriptions.append("Added move: \(fileName) → \(dest)")

            case "removeMove":
                guard let fileName = mod.fileName else { continue }
                for i in plan.moveActions.indices {
                    if plan.moveActions[i].fileName.localizedCaseInsensitiveContains(fileName) {
                        plan.moveActions[i].accepted = false
                        changeDescriptions.append("Excluded: \(plan.moveActions[i].fileName)")
                    }
                }

            case "changeDestination":
                guard let fileName = mod.fileName, let dest = mod.destinationPath else { continue }
                for i in plan.moveActions.indices {
                    if plan.moveActions[i].fileName.localizedCaseInsensitiveContains(fileName) {
                        let old = plan.moveActions[i].destinationPath
                        plan.moveActions[i].destinationPath = dest
                        plan.moveActions[i].reason = mod.reason ?? "Changed by AI chat"
                        changeDescriptions.append("Moved \(plan.moveActions[i].fileName): \(old) → \(dest)")
                    }
                }

            case "addCleanup":
                guard let fileName = mod.fileName else { continue }
                let newClutter = ClutterAction(
                    path: mod.sourcePath ?? fileName,
                    action: .delete,
                    reason: mod.reason ?? "Flagged by AI chat",
                    size: 0,
                    accepted: true
                )
                plan.clutterActions.append(newClutter)
                changeDescriptions.append("Added to cleanup: \(fileName)")

            case "removeCleanup":
                guard let fileName = mod.fileName else { continue }
                for i in plan.clutterActions.indices {
                    if plan.clutterActions[i].path.localizedCaseInsensitiveContains(fileName) {
                        plan.clutterActions[i].accepted = false
                        changeDescriptions.append("Removed from cleanup: \(plan.clutterActions[i].path)")
                    }
                }

            case "addRename":
                guard let fileName = mod.fileName, let newName = mod.destinationPath else { continue }
                let rename = RenameSuggestion(
                    filePath: mod.sourcePath ?? "",
                    originalName: fileName,
                    suggestedName: newName,
                    reason: mod.reason ?? "Suggested by AI chat",
                    accepted: true
                )
                plan.renameSuggestions.append(rename)
                changeDescriptions.append("Rename: \(fileName) → \(newName)")

            default:
                break
            }
        }

        return changeDescriptions
    }

    static func applyPreferenceChanges(
        _ changes: [PreferenceChange],
        to preferences: inout OrganizationPreferences
    ) {
        for change in changes {
            switch change.field {
            case "folderStructure":
                if let val = FolderStructurePreference(rawValue: change.value) {
                    preferences.folderStructure = val
                }
            case "namingConvention":
                if let val = NamingConventionPreference(rawValue: change.value) {
                    preferences.namingConvention = val
                }
            case "duplicatesHandling":
                if let val = DuplicatesHandlingPreference(rawValue: change.value) {
                    preferences.duplicatesHandling = val
                }
            case "scope":
                if let val = OrganizationScopePreference(rawValue: change.value) {
                    preferences.scope = val
                }
            case "customRootFolderName":
                preferences.customRootFolderName = change.value
            case "customNamePrefix":
                preferences.customNamePrefix = change.value
            case "splitInstallersByPlatform":
                preferences.splitInstallersByPlatform = change.value.lowercased() == "true"
            case "useSoftDelete":
                preferences.cleanup.useSoftDelete = change.value.lowercased() == "true"
            case "useExiftool":
                preferences.useExiftool = change.value.lowercased() == "true"
            case "generateManifests":
                preferences.generateManifests = change.value.lowercased() == "true"
            default:
                break
            }
        }
    }
}

// MARK: - Refinement Result

struct RefinementResult {
    var planModifications: [PlanModification]?
    var preferenceChanges: [PreferenceChange]?
    var shouldReAnalyze: Bool

    static let empty = RefinementResult(planModifications: nil, preferenceChanges: nil, shouldReAnalyze: false)
}
