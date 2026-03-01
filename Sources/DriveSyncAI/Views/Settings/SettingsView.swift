// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings view with General, Safety, AI Features, Appearance, Achievements, and Advanced sections.
struct SettingsView: View {
    @AppStorage("defaultSyncDirection") private var defaultDirection: String = SyncDirection.oneWayUpdate.rawValue
    @AppStorage("defaultScanMode") private var defaultScanMode: String = ScanMode.smart.rawValue
    @AppStorage("journalRetentionDays") private var journalRetentionDays: Int = 30
    @AppStorage("verifyAfterWrite") private var verifyAfterWrite: Bool = true
    @AppStorage("maxDeleteThreshold") private var maxDeleteThreshold: Double = 50
    @AppStorage("dryRunDefault") private var dryRunDefault: Bool = false
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("reduceAnimations") private var reduceAnimations: Bool = false
    @AppStorage("achievementsEnabled") private var achievementsEnabled: Bool = false
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false

    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var llmConfigManager: LLMConfigManager
    @EnvironmentObject var customRulesService: CustomRulesService
    @StateObject private var chatService = SettingsChatService()
    @State private var showClearJournalAlert = false
    @State private var showAchievementsSheet = false
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var showLLMSettings = false
    @State private var showCustomRules = false
    @State private var showChatPanel = true
    @State private var chatInput = ""

    private var syncDirectionBinding: Binding<SyncDirection> {
        Binding(
            get: { SyncDirection(rawValue: defaultDirection) ?? .oneWayUpdate },
            set: { defaultDirection = $0.rawValue }
        )
    }

    private var scanModeBinding: Binding<ScanMode> {
        Binding(
            get: { ScanMode(rawValue: defaultScanMode) ?? .smart },
            set: { defaultScanMode = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    AIChatToggleButton(isVisible: $showChatPanel)
                }
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, AppTheme.Spacing.small)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        generalSection
                        safetySection
                        aiSection
                        appearanceSection
                        achievementsSection
                        advancedSection
                    }
                    .padding(AppTheme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
            .alert("Clear Journal History", isPresented: $showClearJournalAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearJournalHistory()
                }
            } message: {
                Text("This will delete all journal and backup files. Incomplete operations cannot be recovered. Continue?")
            }
            .alert("Export complete", isPresented: $showExportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Logs have been exported successfully.")
            }
            .alert("Export failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not export logs.")
            }
            .sheet(isPresented: $showAchievementsSheet) {
                AchievementsView()
                    .environmentObject(achievementService)
                    .frame(minWidth: 600, minHeight: 500)
            }
            .sheet(isPresented: $showLLMSettings) {
                LLMSettingsView()
                    .environmentObject(llmConfigManager)
            }
            .sheet(isPresented: $showCustomRules) {
                CustomRulesEditorView()
                    .environmentObject(customRulesService)
            }
            .onAppear {
                chatService.addWelcomeMessage()
            }

            if showChatPanel {
                AIChatPanelView(
                    title: "DriveSyncAI Buddy",
                    placeholder: "Ask about any setting...",
                    messages: chatService.messages,
                    input: $chatInput,
                    isLoading: chatService.isLoading,
                    quickActions: [
                        "Recommend settings for me",
                        "How do I set up Ollama?",
                        "What does parallel I/O do?",
                    ],
                    onSend: { sendSettingsMessage() },
                    onClose: { showChatPanel = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showChatPanel)
    }

    private func sendSettingsMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        chatInput = ""

        let snapshot = SettingsSnapshot(
            syncDirection: defaultDirection,
            scanMode: defaultScanMode,
            journalRetentionDays: journalRetentionDays,
            verifyAfterWrite: verifyAfterWrite,
            maxDeleteThreshold: Int(maxDeleteThreshold),
            dryRunDefault: dryRunDefault,
            appearance: appearance,
            aiEnabled: aiEnabled,
            llmProvider: llmConfigManager.activeProvider.displayName,
            llmModel: llmConfigManager.activeModel,
            llmStatus: llmConfigManager.connectionStatus == .connected ? "Connected" : "Not connected",
            achievementsEnabled: achievementsEnabled
        )

        Task {
            await chatService.send(
                userText: text,
                settings: snapshot,
                configManager: llmConfigManager
            )
        }
    }

    // MARK: - General

    private var generalSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("General")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        Text("Default sync direction")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsPrimaryText)
                        Spacer()
                        Picker("", selection: syncDirectionBinding) {
                            Text("Mirror →").tag(SyncDirection.oneWayMirror)
                            Text("Update →").tag(SyncDirection.oneWayUpdate)
                            Text("Sync ↔").tag(SyncDirection.bidirectional)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Default scan mode")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsPrimaryText)
                        Spacer()
                        Picker("", selection: scanModeBinding) {
                            Text("Quick").tag(ScanMode.quick)
                            Text("Smart").tag(ScanMode.smart)
                            Text("Deep").tag(ScanMode.deep)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Journal retention (days)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsPrimaryText)
                        Spacer()
                        Stepper(value: $journalRetentionDays, in: 1...365) {
                            Text("\(journalRetentionDays)")
                                .font(.system(size: 13, weight: .medium))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                        .frame(width: 120)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Safety

    private var safetySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Safety")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Toggle("Verify after write", isOn: $verifyAfterWrite)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        HStack {
                            Text("Max delete threshold")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsPrimaryText)
                            Spacer()
                            Text("\(Int(maxDeleteThreshold))%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                        Slider(value: $maxDeleteThreshold, in: 10...90, step: 5)
                    }

                    Toggle("Dry run default", isOn: $dryRunDefault)
                        .toggleStyle(.switch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - AI Features

    private var aiSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("AI Features")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                Toggle("Enable AI-powered organization", isOn: $aiEnabled)
                    .font(.system(size: 13))

                if aiEnabled {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LLM Provider")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsPrimaryText)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(llmConfigManager.connectionStatus == .connected ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text("\(llmConfigManager.activeProvider.displayName) / \(llmConfigManager.activeModel)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.dsSecondaryText)
                            }
                        }
                        Spacer()
                        Button("Configure") { showLLMSettings = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom Rules")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsPrimaryText)
                            Text("\(customRulesService.enabledRules.count) active rules")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                        Spacer()
                        Button("Manage") { showCustomRules = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                            .font(.system(size: 12))
                        Text("AI features use Ollama by default for local, private processing. Configure cloud providers in LLM settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Appearance")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        Text("Theme")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsPrimaryText)
                        Spacer()
                        Picker("", selection: $appearance) {
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                            Text("System").tag("system")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Toggle("Reduce animations", isOn: $reduceAnimations)
                        .toggleStyle(.switch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Achievements")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Toggle("Enable achievements", isOn: $achievementsEnabled)
                        .toggleStyle(.switch)

                    if achievementsEnabled {
                        GlassButton("View Achievements", icon: "trophy.fill", style: .secondary) {
                            showAchievementsSheet = true
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Advanced")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Text("Journal location")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)
                        Text(SafetyService.journalDirectory.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.dsPrimaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: AppTheme.Spacing.medium) {
                        GlassButton("Clear Journal History", icon: "trash", style: .destructive) {
                            showClearJournalAlert = true
                        }

                        GlassButton("Export Logs", icon: "square.and.arrow.up", style: .secondary) {
                            exportLogs()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func clearJournalHistory() {
        let journalDir = SafetyService.journalDirectory
        let fm = FileManager.default
        guard fm.fileExists(atPath: journalDir.path) else { return }

        do {
            let contents = try fm.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil)
            for url in contents {
                try? fm.removeItem(at: url)
            }
            let backupsDir = journalDir.appendingPathComponent("backups", isDirectory: true)
            if fm.fileExists(atPath: backupsDir.path) {
                let backupContents = try fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
                for url in backupContents {
                    try? fm.removeItem(at: url)
                }
            }
        } catch {}
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "DriveSyncAI_logs_\(formattedDateForFile()).txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let journalDir = SafetyService.journalDirectory
        let fm = FileManager.default
        var logText = "DriveSyncAI Export\n"
        logText += "Exported: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        if fm.fileExists(atPath: journalDir.path) {
            do {
                let contents = try fm.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                for fileURL in contents.sorted(by: { ($0.lastPathComponent) < ($1.lastPathComponent) }) {
                    if fileURL.pathExtension == "jsonl" {
                        logText += "=== \(fileURL.lastPathComponent) ===\n"
                        if let data = try? Data(contentsOf: fileURL),
                           let str = String(data: data, encoding: .utf8) {
                            logText += str
                            logText += "\n\n"
                        }
                    }
                }
            } catch {
                showExportError = true
                return
            }
        }

        do {
            try logText.write(to: url, atomically: true, encoding: .utf8)
            showExportSuccess = true
        } catch {
            showExportError = true
        }
    }

    private func formattedDateForFile() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
