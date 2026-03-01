// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

@MainActor
final class DuplicateChatService: ObservableObject {
    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var pendingResult: DuplicateRefinementResult?

    private var conversationHistory: [(role: String, content: String)] = []

    func clear() {
        messages = []
        conversationHistory = []
        isLoading = false
        lastError = nil
        pendingResult = nil
    }

    func addWelcomeMessage(groupCount: Int, wastedSpace: String) {
        if messages.contains(where: { $0.isStatusMessage && $0.role == "assistant" }) { return }
        let msg = "I can help you manage duplicates. " +
            "\(groupCount) duplicate groups (\(wastedSpace) recoverable) found. Try:\n" +
            "• \"Keep the newest copy of each\"\n" +
            "• \"Select all duplicate photos\"\n" +
            "• \"How much space from videos?\"\n" +
            "• \"Select duplicates larger than 100MB\""
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    func clearPendingResult() {
        pendingResult = nil
    }

    // MARK: - Send Message

    @discardableResult
    func send(
        userText: String,
        groups: [DuplicateGroup],
        configManager: LLMConfigManager
    ) async -> DuplicateRefinementResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        messages.append(OrganizationChatMessage(role: "user", text: trimmed))
        conversationHistory.append((role: "user", content: trimmed))
        isLoading = true
        lastError = nil
        pendingResult = nil

        let service = configManager.currentService()
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(text: trimmed, groups: groups)

        do {
            let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
            guard let json = LLMResponseValidator.extractJSON(from: response),
                  let data = json.data(using: .utf8) else {
                throw LLMError.invalidJSON("Could not extract JSON from response")
            }

            let decoded = try JSONDecoder().decode(DuplicateRefinementResponse.self, from: data)

            var assistantText = [decoded.assistantMessage, decoded.followUpQuestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")

            let result = buildResult(from: decoded, groups: groups)

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

    // MARK: - Prompts

    private func buildSystemPrompt() -> String {
        """
        You are a duplicate file assistant for DriveSyncAI, a macOS file management application. \
        The user has scanned a drive and found duplicate files grouped by identical content hash. \
        You help the user understand, filter, and select which duplicates to remove.

        CAPABILITIES:
        - Answer questions about duplicates: counts, sizes, categories, largest groups
        - Smart select strategies: keep newest, keep oldest, keep shortest path
        - Select/deselect by file category, folder, or minimum size
        - Select all or deselect all marked files

        RULES:
        - Be concise — 1-3 sentences max.
        - For informational queries (counts, sizes, categories), set ONLY assistantMessage. Do NOT include changes.
        - For action queries, include selectionChanges AND a summary in assistantMessage.
        - "Keep the newest" means mark all EXCEPT the newest in each group for removal → smartSelectKeepNewest.
        - "Keep the oldest" means mark all EXCEPT the oldest → smartSelectKeepOldest.
        - "Select all duplicate photos" means selectByCategory with target "photos".
        - Never auto-apply. The user must click Apply.

        RESPONSE FORMAT (JSON only, no markdown):
        {
          "assistantMessage": "Your response to the user",
          "followUpQuestion": "Optional clarifying question or null",
          "selectionChanges": [{"action": "smartSelectKeepNewest"}]
        }

        SELECTION ACTIONS:
        - selectAll / deselectAll: mark all / unmark all duplicates
        - smartSelectKeepNewest: in each group, keep the newest file, mark the rest for removal
        - smartSelectKeepOldest: in each group, keep the oldest file, mark the rest
        - smartSelectKeepShortestPath: in each group, keep the file with shortest path
        - selectByCategory / deselectByCategory: target = "photos", "videos", "documents", "music", "archives", "other"
        - selectByFolder / deselectByFolder: target = folder path prefix
        - selectByMinSize: mark duplicates in groups where per-file size >= threshold (e.g. "100MB", "1GB")

        CATEGORIES: photos, videos, documents, music, archives, other
        """
    }

    private func buildUserPrompt(text: String, groups: [DuplicateGroup]) -> String {
        var parts: [String] = []

        if conversationHistory.count > 1 {
            let recent = conversationHistory.suffix(10)
            let historyText = recent.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        let totalGroups = groups.count
        let totalFiles = groups.reduce(0) { $0 + $1.files.count }
        let totalWaste = groups.reduce(UInt64(0)) { $0 + $1.wastedSpace }
        let selectedCount = groups.reduce(0) { $0 + $1.files.filter(\.isSelected).count }

        var catCounts: [String: Int] = [:]
        var catSizes: [String: UInt64] = [:]
        for group in groups {
            for file in group.files {
                let ext = (file.fileInfo.name as NSString).pathExtension
                let cat = DuplicateFinderService.FileCategory.category(for: ext)
                catCounts[cat.displayName, default: 0] += 1
                catSizes[cat.displayName, default: 0] += file.fileInfo.size
            }
        }

        let catBreakdown = catCounts.sorted { $0.value > $1.value }.map { key, count in
            let size = ByteCountFormatter.string(fromByteCount: Int64(catSizes[key] ?? 0), countStyle: .file)
            return "  \(key): \(count) files (\(size))"
        }.joined(separator: "\n")

        let topFolders = Dictionary(grouping: groups.flatMap(\.files)) { file -> String in
            let components = file.fileInfo.relativePath.split(separator: "/")
            return components.count > 1 ? String(components[0]) : "(root)"
        }
        .sorted { $0.value.count > $1.value.count }
        .prefix(10)
        .map { "  \($0.key): \($0.value.count) files" }
        .joined(separator: "\n")

        parts.append("""
        DUPLICATE SUMMARY:
        - Total groups: \(totalGroups)
        - Total files (including originals): \(totalFiles)
        - Wasted space: \(ByteCountFormatter.string(fromByteCount: Int64(totalWaste), countStyle: .file))
        - Currently marked for removal: \(selectedCount)

        BY CATEGORY:
        \(catBreakdown)
        """)

        if !topFolders.isEmpty {
            parts.append("TOP FOLDERS:\n\(topFolders)")
        }

        let largest = groups.sorted { $0.wastedSpace > $1.wastedSpace }.prefix(5)
        if !largest.isEmpty {
            let largestText = largest.map { group in
                let name = group.files.first?.fileInfo.name ?? "unknown"
                let waste = ByteCountFormatter.string(fromByteCount: Int64(group.wastedSpace), countStyle: .file)
                return "  \(name) — \(group.files.count) copies, \(waste) wasted"
            }.joined(separator: "\n")
            parts.append("LARGEST DUPLICATE GROUPS:\n\(largestText)")
        }

        parts.append("USER MESSAGE:\n\(text)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Build Result

    private func buildResult(from decoded: DuplicateRefinementResponse, groups: [DuplicateGroup]) -> DuplicateRefinementResult {
        let changes = (decoded.selectionChanges ?? []).filter {
            DuplicateSelectionChange.validActions.contains($0.action)
        }

        var summaryParts: [String] = []
        for change in changes {
            switch change.action {
            case "selectAll":
                summaryParts.append("Mark all duplicates for removal")
            case "deselectAll":
                summaryParts.append("Unmark all duplicates")
            case "smartSelectKeepNewest":
                summaryParts.append("Keep newest copy, mark the rest")
            case "smartSelectKeepOldest":
                summaryParts.append("Keep oldest copy, mark the rest")
            case "smartSelectKeepShortestPath":
                summaryParts.append("Keep shortest path, mark the rest")
            case "selectByCategory":
                summaryParts.append("Mark \(change.target ?? "") duplicates")
            case "deselectByCategory":
                summaryParts.append("Unmark \(change.target ?? "") duplicates")
            case "selectByFolder":
                summaryParts.append("Mark duplicates in \(change.target ?? "folder")")
            case "deselectByFolder":
                summaryParts.append("Unmark duplicates in \(change.target ?? "folder")")
            case "selectByMinSize":
                summaryParts.append("Mark duplicates larger than \(change.threshold ?? "")")
            default:
                break
            }
        }

        let summary = summaryParts.joined(separator: ". ") + (summaryParts.isEmpty ? "" : ".")

        return DuplicateRefinementResult(
            selectionChanges: changes,
            summary: summary
        )
    }
}
