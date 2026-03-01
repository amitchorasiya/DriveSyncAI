// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

/// Lightweight informational chat service for setup / configuration screens
/// (Sync setup, Duplicate scan config). Answers questions and gives tips
/// but cannot execute actions.
@MainActor
final class SetupBuddyChatService: ObservableObject {
    enum Screen: String {
        case sync
        case duplicates
    }

    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private var conversationHistory: [(role: String, content: String)] = []
    private var hasShownWelcome = false
    let screen: Screen

    init(screen: Screen) {
        self.screen = screen
    }

    func addWelcomeMessage() {
        guard !hasShownWelcome else { return }
        hasShownWelcome = true

        let msg: String
        switch screen {
        case .sync:
            msg = "Hi! I'm your DriveSyncAI Buddy. I can help you set up a sync:\n" +
                "• \"What's the difference between Mirror and Update?\"\n" +
                "• \"Should I use parallel file operations?\"\n" +
                "• \"How do filters work?\""
        case .duplicates:
            msg = "Hi! I'm your DriveSyncAI Buddy. I can help configure your duplicate scan:\n" +
                "• \"Which scan mode should I use?\"\n" +
                "• \"What do the categories filter?\"\n" +
                "• \"How accurate is the Smart scan?\""
        }
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    @discardableResult
    func send(
        userText: String,
        drives: [DriveInfo],
        configManager: LLMConfigManager
    ) async -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        messages.append(OrganizationChatMessage(role: "user", text: trimmed))
        conversationHistory.append((role: "user", content: trimmed))
        isLoading = true
        lastError = nil

        let service = configManager.currentService()
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(text: trimmed, drives: drives)

        do {
            let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

            messages.append(OrganizationChatMessage(role: "assistant", text: cleaned))
            conversationHistory.append((role: "assistant", content: cleaned))
            isLoading = false
            return cleaned
        } catch {
            lastError = error.localizedDescription
            let errMsg = "Sorry, I couldn't process that. Please try again."
            messages.append(OrganizationChatMessage(role: "assistant", text: errMsg))
            conversationHistory.append((role: "assistant", content: errMsg))
            isLoading = false
            return errMsg
        }
    }

    // MARK: - Prompts

    private func buildSystemPrompt() -> String {
        switch screen {
        case .sync:
            return """
            You are DriveSyncAI Buddy, an assistant on the Sync tab of DriveSyncAI (a macOS file manager). \
            The user is configuring a sync operation between two drives.

            KNOWLEDGE:
            - Mirror →: Makes target an exact copy of source. Deletes files on target that don't exist on source.
            - Update →: Copies new/changed files from source to target. Never deletes.
            - Sync ↔: Two-way sync. Newer file wins on both sides.
            - Filters: Let users exclude file types or patterns (e.g. .DS_Store, node_modules).
            - Profiles: Saved configurations for repeated syncs.
            - Parallel File Operations: Copies multiple files at once. Faster for many small files. \
              Concurrency auto-tuned by drive type (USB 2.0=2, USB 3.x=4, Thunderbolt=6, NVMe=8).
            - After clicking Compare, the app shows a tree view of all changes before syncing.

            RULES:
            - Be concise — 1-3 sentences.
            - You are informational only — you cannot change settings or start a sync.
            - Do NOT wrap your response in JSON. Reply in plain text.
            """
        case .duplicates:
            return """
            You are DriveSyncAI Buddy, an assistant on the Duplicates tab of DriveSyncAI (a macOS file manager). \
            The user is configuring a duplicate file scan.

            KNOWLEDGE:
            - Quick scan: Matches by name + size only. Fastest but may miss renamed duplicates.
            - Smart scan: Partial hash first, then full hash for candidates. Good balance of speed and accuracy.
            - Deep scan: Full SHA256 hash for every file. Most accurate but slowest.
            - Categories: Photos, Videos, Documents, Music, Archives, Other. Users pick which to include.
            - Exclusions: Can exclude system files (.DS_Store, etc.) and hidden files (dot-files).
            - Parallel File Operations: Moves multiple duplicates at once after scan.
            - After scanning, the app shows duplicate groups with AI-assisted selection.

            RULES:
            - Be concise — 1-3 sentences.
            - You are informational only — you cannot start a scan or change settings.
            - Do NOT wrap your response in JSON. Reply in plain text.
            """
        }
    }

    private func buildUserPrompt(text: String, drives: [DriveInfo]) -> String {
        var parts: [String] = []

        if conversationHistory.count > 1 {
            let recent = conversationHistory.suffix(8)
            let historyText = recent.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        if !drives.isEmpty {
            let driveInfo = drives.map { drive in
                let total = ByteCountFormatter.string(fromByteCount: Int64(drive.totalCapacity), countStyle: .file)
                let free = ByteCountFormatter.string(fromByteCount: Int64(drive.availableCapacity), countStyle: .file)
                return "  \(drive.name): \(total) total, \(free) free — \(drive.connectionType.rawValue)"
            }.joined(separator: "\n")
            parts.append("AVAILABLE DRIVES (\(drives.count)):\n\(driveInfo)")
        }

        parts.append("USER MESSAGE:\n\(text)")
        return parts.joined(separator: "\n\n")
    }
}
