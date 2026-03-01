// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

@MainActor
final class SyncChatService: ObservableObject {
    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var pendingResult: SyncRefinementResult?

    private var conversationHistory: [(role: String, content: String)] = []

    func clear() {
        messages = []
        conversationHistory = []
        isLoading = false
        lastError = nil
        pendingResult = nil
    }

    func addWelcomeMessage(actionCount: Int, totalSize: String) {
        if messages.contains(where: { $0.isStatusMessage && $0.role == "assistant" }) { return }
        let msg = "I can help you filter and select files for sync. " +
            "\(actionCount) files (\(totalSize)) are ready. Try:\n" +
            "• \"Sync only images\"\n" +
            "• \"Skip archives\"\n" +
            "• \"Don't delete anything\"\n" +
            "• \"How many conflicts?\""
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    // MARK: - Send Message

    @discardableResult
    func send(
        userText: String,
        actions: [SyncAction],
        activeFilters: Set<FileTypeCategory>,
        syncDirection: SyncDirection,
        configManager: LLMConfigManager
    ) async -> SyncRefinementResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        messages.append(OrganizationChatMessage(role: "user", text: trimmed))
        conversationHistory.append((role: "user", content: trimmed))
        isLoading = true
        lastError = nil
        pendingResult = nil

        let service = configManager.currentService()
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            text: trimmed,
            actions: actions,
            activeFilters: activeFilters,
            syncDirection: syncDirection
        )

        do {
            let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
            guard let json = LLMResponseValidator.extractJSON(from: response),
                  let data = json.data(using: .utf8) else {
                throw LLMError.invalidJSON("Could not extract JSON from response")
            }

            let decoded = try JSONDecoder().decode(SyncRefinementResponse.self, from: data)

            var assistantText = [decoded.assistantMessage, decoded.followUpQuestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")

            let result = buildResult(from: decoded, actions: actions)

            if assistantText.isEmpty && result.hasChanges {
                assistantText = result.summary
            }

            if !assistantText.isEmpty {
                messages.append(OrganizationChatMessage(role: "assistant", text: assistantText))
                conversationHistory.append((role: "assistant", content: assistantText))
            }

            if result.hasChanges {
                pendingResult = result
            }

            isLoading = false
            return result
        } catch {
            lastError = error.localizedDescription
            messages.append(
                OrganizationChatMessage(
                    role: "assistant",
                    text: "Sorry, I couldn't process that. Could you rephrase your request?"
                )
            )
            conversationHistory.append((role: "assistant", content: "Error processing request."))
            isLoading = false
            return .empty
        }
    }

    func clearPendingResult() {
        pendingResult = nil
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        """
        You are a sync assistant for DriveSyncAI, a macOS file sync application. The user is reviewing \
        a list of file sync actions (create, update, delete, conflict, skip) before executing them. \
        You help the user filter, select, and understand the sync actions through natural language.

        CAPABILITIES:
        - Answer questions about the sync: file counts, sizes, conflicts, largest files
        - Filter by file type category: toggle visibility of photos, videos, documents, music, archives, code, other
        - Select/deselect files by folder, action type, extension, size, or date
        - Change sync direction (requires user confirmation)
        - Expand folders in the tree view

        RULES:
        - Be concise — 1-3 sentences max.
        - For informational queries (counts, sizes, conflicts), set ONLY assistantMessage. Do NOT include any changes.
        - For action queries (sync only X, skip Y, deselect Z), include the appropriate changes AND a summary.
        - CRITICAL: "sync only photos" or "filter only photos" or "select only images" means: deselectAll FIRST, \
        then selectByCategory with the matching category. Always use BOTH steps so non-matching files are deselected.
        - When the user says "also include X" or "add X", keep current selections and additionally select X.
        - When the user says "skip X" or "exclude X", deselect X but keep everything else.
        - "Don't delete anything" means deselect all actions with actionType "delete".
        - ALWAYS prefer selectByCategory/deselectByCategory over selectByExtension when the user mentions a category \
        name like "photos", "images", "videos", "documents", "music", "archives", or "code". \
        Each category covers 15-30+ file extensions comprehensively (e.g. photos includes jpg, png, heic, raw, cr2, nef, arw, dng, psd, etc.).
        - For direction changes, ALWAYS include directionChange but explain it will need confirmation.
        - Never auto-apply. The user must click Apply.

        RESPONSE FORMAT (JSON only, no markdown):
        {
          "assistantMessage": "Your response to the user",
          "followUpQuestion": "A clarifying question if needed, or null",
          "filterChanges": [{"category": "photos", "active": true}],
          "selectionChanges": [{"action": "deselectAll"}, {"action": "selectByCategory", "target": "photos"}],
          "directionChange": "oneWayMirror or oneWayUpdate or bidirectional, or null",
          "expandFolders": ["FolderName"]
        }

        SELECTION ACTIONS:
        - selectAll / deselectAll: target=null
        - selectFolder / deselectFolder: target="FolderPath" (relative path prefix)
        - selectByActionType / deselectByActionType: target="create" or "update" or "delete" or "conflict" or "skip"
        - selectByExtension / deselectByExtension: target="pdf" (file extension without dot)
        - selectByCategory / deselectByCategory: target="photos" or "videos" or "documents" or "music" or \
        "archives" or "code" or "other". Matches ALL file extensions in that category at once.
        - selectByMinSize / deselectByMinSize: threshold="10MB" or "1GB"
        - selectByDateAfter / deselectByDateBefore: threshold="2026-01-01" (ISO date)

        FILTER CATEGORIES: photos, videos, documents, music, archives, code, other

        EXAMPLES:
        - "sync only photos" → selectionChanges: [{"action":"deselectAll"},{"action":"selectByCategory","target":"photos"}]
        - "also include videos" → selectionChanges: [{"action":"selectByCategory","target":"videos"}]
        - "skip archives" → selectionChanges: [{"action":"deselectByCategory","target":"archives"}]
        - "sync only .pdf files" → selectionChanges: [{"action":"deselectAll"},{"action":"selectByExtension","target":"pdf"}]
        """
    }

    // MARK: - User Prompt

    private func buildUserPrompt(
        text: String,
        actions: [SyncAction],
        activeFilters: Set<FileTypeCategory>,
        syncDirection: SyncDirection
    ) -> String {
        var parts: [String] = []

        if conversationHistory.count > 1 {
            let recent = conversationHistory.suffix(10)
            let historyText = recent.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        let directionLabel: String
        switch syncDirection {
        case .oneWayMirror: directionLabel = "One-way Mirror"
        case .oneWayUpdate: directionLabel = "One-way Update"
        case .bidirectional: directionLabel = "Bidirectional"
        }

        let totalSize = actions.reduce(UInt64(0)) { $0 + $1.fileSize }
        let selectedCount = actions.filter(\.isSelected).count

        var typeCounts: [String: Int] = [:]
        var typeSizes: [String: UInt64] = [:]
        for action in actions {
            let ext = (action.relativePath as NSString).pathExtension
            let cat = FileTypeCategory.category(for: ext)
            typeCounts[cat.label, default: 0] += 1
            typeSizes[cat.label, default: 0] += action.fileSize
        }

        let typeBreakdown = typeCounts.sorted { $0.value > $1.value }.map { key, count in
            let size = ByteCountFormatter.string(fromByteCount: Int64(typeSizes[key] ?? 0), countStyle: .file)
            return "  \(key): \(count) files (\(size))"
        }.joined(separator: "\n")

        var actionTypeCounts: [String: Int] = [:]
        for action in actions {
            actionTypeCounts[action.actionType.rawValue, default: 0] += 1
        }
        let actionBreakdown = actionTypeCounts.sorted { $0.key < $1.key }.map { key, count in
            "  \(key): \(count)"
        }.joined(separator: "\n")

        let activeFilterNames = activeFilters.map(\.label).sorted().joined(separator: ", ")

        parts.append("""
        SYNC SUMMARY:
        - Direction: \(directionLabel)
        - Total files: \(actions.count)
        - Selected: \(selectedCount) of \(actions.count)
        - Total size: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))
        - Active file type filters: \(activeFilterNames)

        BY FILE TYPE:
        \(typeBreakdown)

        BY ACTION TYPE:
        \(actionBreakdown)
        """)

        let topFolders = Dictionary(grouping: actions) { action -> String in
            let components = action.relativePath.split(separator: "/")
            return components.count > 1 ? String(components[0]) : "(root)"
        }
        .sorted { $0.value.count > $1.value.count }
        .prefix(15)
        .map { "  \($0.key): \($0.value.count) files" }
        .joined(separator: "\n")

        if !topFolders.isEmpty {
            parts.append("TOP FOLDERS:\n\(topFolders)")
        }

        parts.append("USER MESSAGE:\n\(text)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Build Result

    private func buildResult(from decoded: SyncRefinementResponse, actions: [SyncAction]) -> SyncRefinementResult {
        let filterChanges = decoded.filterChanges ?? []
        let selectionChanges = (decoded.selectionChanges ?? []).filter {
            SyncSelectionChange.validActions.contains($0.action)
        }
        let expandFolders = decoded.expandFolders ?? []

        let summary = buildSummary(
            filterChanges: filterChanges,
            selectionChanges: selectionChanges,
            directionChange: decoded.directionChange,
            actions: actions
        )

        return SyncRefinementResult(
            filterChanges: filterChanges,
            selectionChanges: selectionChanges,
            directionChange: decoded.directionChange,
            expandFolders: expandFolders,
            summary: summary
        )
    }

    private func buildSummary(
        filterChanges: [SyncFilterChange],
        selectionChanges: [SyncSelectionChange],
        directionChange: String?,
        actions: [SyncAction]
    ) -> String {
        var parts: [String] = []

        if !filterChanges.isEmpty {
            let enabling = filterChanges.filter(\.active).map(\.category)
            let disabling = filterChanges.filter { !$0.active }.map(\.category)
            if !enabling.isEmpty {
                parts.append("Show \(enabling.joined(separator: ", "))")
            }
            if !disabling.isEmpty {
                parts.append("Hide \(disabling.joined(separator: ", "))")
            }
        }

        if !selectionChanges.isEmpty {
            for change in selectionChanges {
                switch change.action {
                case "selectAll":
                    parts.append("Select all \(actions.count) files")
                case "deselectAll":
                    parts.append("Deselect all files")
                case "selectFolder":
                    parts.append("Select files in \(change.target ?? "folder")")
                case "deselectFolder":
                    parts.append("Deselect files in \(change.target ?? "folder")")
                case "selectByActionType":
                    parts.append("Select all \(change.target ?? "") actions")
                case "deselectByActionType":
                    parts.append("Deselect all \(change.target ?? "") actions")
                case "selectByExtension":
                    parts.append("Select .\(change.target ?? "") files")
                case "deselectByExtension":
                    parts.append("Deselect .\(change.target ?? "") files")
                case "selectByCategory":
                    parts.append("Select all \(change.target ?? "") files")
                case "deselectByCategory":
                    parts.append("Deselect all \(change.target ?? "") files")
                case "selectByMinSize":
                    parts.append("Select files larger than \(change.threshold ?? "")")
                case "deselectByMinSize":
                    parts.append("Deselect files larger than \(change.threshold ?? "")")
                case "selectByDateAfter":
                    parts.append("Select files after \(change.threshold ?? "")")
                case "deselectByDateBefore":
                    parts.append("Deselect files before \(change.threshold ?? "")")
                default:
                    break
                }
            }
        }

        if let dir = directionChange {
            parts.append("Change direction to \(dir) (requires confirmation)")
        }

        return parts.joined(separator: ". ") + (parts.isEmpty ? "" : ".")
    }
}
