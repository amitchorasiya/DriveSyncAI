// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

@MainActor
final class SettingsChatService: ObservableObject {
    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private var conversationHistory: [(role: String, content: String)] = []
    private var hasShownWelcome = false

    func addWelcomeMessage() {
        guard !hasShownWelcome else { return }
        hasShownWelcome = true
        let msg = "I can explain any setting or recommend configurations. Try:\n" +
            "• \"What does dry run mode do?\"\n" +
            "• \"Should I enable verify after write?\"\n" +
            "• \"Best settings for external SSD sync?\"\n" +
            "• \"Explain the delete threshold\""
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    @discardableResult
    func send(
        userText: String,
        settings: SettingsSnapshot,
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
        let userPrompt = buildUserPrompt(text: trimmed, settings: settings)

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
        """
        You are a settings assistant for DriveSyncAI, a macOS file management application. \
        The user is on the Settings tab and wants to understand or get recommendations for their configuration.

        CAPABILITIES:
        - Explain what each setting does and when to use it
        - Recommend optimal settings based on use case (e.g. syncing to SSD, NAS, USB thumb drive)
        - Explain tradeoffs between safety and speed settings

        SETTINGS REFERENCE:
        - Sync Direction: Mirror (exact copy), Update (add/update only, no deletes), Bidirectional (two-way merge)
        - Scan Mode: Quick (name+size), Smart (partial hash, then full), Deep (full SHA256)
        - Journal Retention: How many days to keep sync/move journals for undo capability
        - Verify After Write: Re-reads each copied file and compares checksums. Slower but catches corruption.
        - Max Delete Threshold: Safety limit — if a sync would delete more than this % of target files, it aborts.
        - Dry Run: Simulates the sync without actually copying/deleting. Great for previewing changes.
        - AI Features: Uses a local LLM (Ollama by default) for smart file organization.
        - Achievements: Gamification — tracks milestones (files synced, space recovered, etc.)

        RULES:
        - Be concise — 1-3 sentences max.
        - You are informational only — you cannot change settings. Tell the user which toggle/slider to adjust.
        - Do NOT wrap your response in JSON. Reply in plain text.
        """
    }

    private func buildUserPrompt(text: String, settings: SettingsSnapshot) -> String {
        var parts: [String] = []

        if conversationHistory.count > 1 {
            let recent = conversationHistory.suffix(8)
            let historyText = recent.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        parts.append("""
        CURRENT SETTINGS:
        - Sync Direction: \(settings.syncDirection)
        - Scan Mode: \(settings.scanMode)
        - Journal Retention: \(settings.journalRetentionDays) days
        - Verify After Write: \(settings.verifyAfterWrite ? "ON" : "OFF")
        - Max Delete Threshold: \(settings.maxDeleteThreshold)%
        - Dry Run Default: \(settings.dryRunDefault ? "ON" : "OFF")
        - Theme: \(settings.appearance)
        - AI Enabled: \(settings.aiEnabled ? "ON" : "OFF")
        - LLM Provider: \(settings.llmProvider) / \(settings.llmModel)
        - LLM Connection: \(settings.llmStatus)
        - Achievements: \(settings.achievementsEnabled ? "ON" : "OFF")
        """)

        parts.append("USER MESSAGE:\n\(text)")

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Settings Snapshot

struct SettingsSnapshot {
    let syncDirection: String
    let scanMode: String
    let journalRetentionDays: Int
    let verifyAfterWrite: Bool
    let maxDeleteThreshold: Int
    let dryRunDefault: Bool
    let appearance: String
    let aiEnabled: Bool
    let llmProvider: String
    let llmModel: String
    let llmStatus: String
    let achievementsEnabled: Bool
}
