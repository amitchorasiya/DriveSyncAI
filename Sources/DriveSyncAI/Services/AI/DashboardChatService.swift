// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import os.log

@MainActor
final class DashboardChatService: ObservableObject {
    private static let log = Logger(subsystem: "com.amitchorasiya.drivesyncai", category: "DashboardChat")

    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private var conversationHistory: [(role: String, content: String)] = []
    private var hasShownWelcome = false

    func addWelcomeMessage(driveCount: Int) {
        guard !hasShownWelcome else { return }
        hasShownWelcome = true
        let msg = welcomeText(driveCount: driveCount)
        messages.append(OrganizationChatMessage(role: "assistant", text: msg, isStatusMessage: true))
    }

    /// Updates the welcome message when drive count changes (e.g. after VolumeMonitor finishes loading).
    func updateWelcomeDriveCount(_ driveCount: Int) {
        guard let idx = messages.firstIndex(where: { $0.role == "assistant" && $0.text.hasPrefix("Welcome to DriveSyncAI!") }) else { return }
        messages[idx] = OrganizationChatMessage(role: "assistant", text: welcomeText(driveCount: driveCount), isStatusMessage: true)
    }

    private func welcomeText(driveCount: Int) -> String {
        "Welcome to DriveSyncAI! You have \(driveCount) drive\(driveCount == 1 ? "" : "s") connected. Ask me anything:\n" +
            "• \"How much free space on my drives?\"\n" +
            "• \"Which drive has the most space?\"\n" +
            "• \"What should I do first?\""
    }

    @discardableResult
    func send(
        userText: String,
        drives: [DriveInfo],
        recentActivities: [RecentActivityItem],
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
        let userPrompt = buildUserPrompt(text: trimmed, drives: drives, activities: recentActivities)

        do {
            Self.log.info("Sending prompt to LLM")
            let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

            messages.append(OrganizationChatMessage(role: "assistant", text: cleaned))
            conversationHistory.append((role: "assistant", content: cleaned))
            isLoading = false
            return cleaned
        } catch {
            lastError = error.localizedDescription
            Self.log.error("Dashboard LLM request failed: \(String(describing: error.localizedDescription))")
            let errMsg = "Sorry, I couldn't process that. Please try again.\n\nError: \(error.localizedDescription)"
            messages.append(OrganizationChatMessage(role: "assistant", text: errMsg))
            conversationHistory.append((role: "assistant", content: errMsg))
            isLoading = false
            return errMsg
        }
    }

    // MARK: - Prompts

    private func buildSystemPrompt() -> String {
        """
        You are a dashboard assistant for DriveSyncAI, a macOS file management application. \
        The user is on the Dashboard tab viewing their connected drives and recent activity.

        CAPABILITIES:
        - Answer questions about connected drives: names, capacity, free space, format, connection type
        - Summarize recent activity (sync completions, duplicate scans)
        - Suggest next actions: sync between drives, find duplicates, organize files
        - Provide general file management tips

        RULES:
        - Be concise and direct — 1-3 sentences max.
        - You are informational only — you cannot change settings or execute actions.
        - When suggesting an action, tell the user which tab to navigate to (Sync, Duplicates, AI Organize).
        - Use the drive data provided to give accurate answers.
        - If the user asks about something outside your scope, suggest the right tab or feature.
        - Do NOT wrap your response in JSON. Reply in plain text.
        """
    }

    private func buildUserPrompt(text: String, drives: [DriveInfo], activities: [RecentActivityItem]) -> String {
        var parts: [String] = []

        if conversationHistory.count > 1 {
            let recent = conversationHistory.suffix(8)
            let historyText = recent.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            parts.append("CONVERSATION HISTORY:\n\(historyText)")
        }

        let driveInfo = drives.map { drive in
            let total = ByteCountFormatter.string(fromByteCount: Int64(drive.totalCapacity), countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: Int64(drive.availableCapacity), countStyle: .file)
            let usedPct = drive.totalCapacity > 0
                ? Int(Double(drive.totalCapacity - drive.availableCapacity) / Double(drive.totalCapacity) * 100)
                : 0
            return "  \(drive.name): \(total) total, \(free) free (\(usedPct)% used) — \(drive.connectionType.rawValue), \(drive.volumeFormat)"
        }.joined(separator: "\n")

        parts.append("CONNECTED DRIVES (\(drives.count)):\n\(driveInfo)")

        if !activities.isEmpty {
            let activityText = activities.prefix(5).map { "  \($0.title): \($0.subtitle ?? "")" }.joined(separator: "\n")
            parts.append("RECENT ACTIVITY:\n\(activityText)")
        } else {
            parts.append("RECENT ACTIVITY: None yet")
        }

        parts.append("USER MESSAGE:\n\(text)")

        return parts.joined(separator: "\n\n")
    }
}
