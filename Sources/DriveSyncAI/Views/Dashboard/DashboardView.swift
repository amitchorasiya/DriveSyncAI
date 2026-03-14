// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct RecentActivityItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let timestamp: Date
    let icon: String
}

struct DashboardView: View {
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var duplicateService: DuplicateFinderService
    @EnvironmentObject var configManager: LLMConfigManager
    @Binding var navigation: NavigationItem?

    @StateObject private var chatService = DashboardChatService()
    @State private var recentActivities: [RecentActivityItem] = []
    @State private var showChatPanel = true
    @State private var chatInput = ""
    @AppStorage("hasAcceptedAIDisclaimer") private var hasAcceptedAIDisclaimer = false

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
                        driveStatusSection
                        quickActionsSection
                        recentActivitySection
                    }
                    .padding(AppTheme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
            .onChange(of: syncService.state) { oldState, newState in
                if oldState == .syncing && newState == .completed {
                    addSyncCompletedActivity()
                }
            }
            .onChange(of: duplicateService.state) { oldState, newState in
                if oldState == .scanning && (newState == .results || newState == .completed) {
                    addDuplicateScanActivity()
                }
            }
            .onAppear {
                chatService.addWelcomeMessage(driveCount: volumeMonitor.mountedVolumes.count)
            }
            .onChange(of: volumeMonitor.mountedVolumes.count) { _, newCount in
                chatService.updateWelcomeDriveCount(newCount)
            }

            if showChatPanel {
                AIChatPanelView(
                    title: "DriveSyncAI Buddy",
                    placeholder: "Ask about your drives...",
                    messages: chatService.messages,
                    input: $chatInput,
                    isLoading: chatService.isLoading,
                    quickActions: [
                        "How much free space?",
                        "Which drive has the most space?",
                        "What should I do first?",
                    ],
                    isDisclaimerAccepted: hasAcceptedAIDisclaimer,
                    onSend: { sendDashboardMessage() },
                    onClose: { showChatPanel = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showChatPanel)
    }

    private func sendDashboardMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        chatInput = ""
        Task {
            await chatService.send(
                userText: text,
                drives: volumeMonitor.mountedVolumes,
                recentActivities: recentActivities,
                configManager: configManager
            )
        }
    }

    private var driveStatusSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Drives")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.large) {
                    ForEach(volumeMonitor.mountedVolumes) { drive in
                        DriveStatusCard(drive: drive)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Quick Actions")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            QuickActionsView(
                navigation: $navigation,
                onSyncNow: { /* Triggers navigation; sync started from Sync view */ },
                onFindDuplicates: {
                    guard duplicateService.targetDrive != nil else { return }
                    Task { await duplicateService.startScan() }
                },
                onCompareOnly: {
                    guard syncService.sourceURL != nil, syncService.targetURL != nil else { return }
                    Task { await syncService.compare() }
                }
            )
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                Spacer()
            }

            GlassCard {
                if recentActivities.isEmpty {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.dsTertiaryText)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No recent activity")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.dsSecondaryText)

                            Text("Sync or scan for duplicates to see activity here")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.dsTertiaryText)
                        }

                        Spacer()
                    }
                    .padding(.vertical, AppTheme.Spacing.medium)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(recentActivities) { item in
                            HStack(spacing: AppTheme.Spacing.medium) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.dsAction)
                                    .frame(width: 24, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.dsPrimaryText)

                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(Color.dsSecondaryText)
                                    }
                                }

                                Spacer()

                                Text(item.timestamp, style: .relative)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.dsTertiaryText)
                            }
                            .padding(.vertical, AppTheme.Spacing.medium)
                            .padding(.horizontal, AppTheme.Spacing.small)

                            if item.id != recentActivities.last?.id {
                                Divider()
                                    .background(Color.dsSeparator)
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addSyncCompletedActivity() {
        let count = syncService.progress.completedFiles
        let subtitle = count == 1 ? "1 file synced" : "\(count) files synced"

        recentActivities.insert(
            RecentActivityItem(
                id: UUID(),
                title: "Sync completed",
                subtitle: subtitle,
                timestamp: Date(),
                icon: "checkmark.circle.fill"
            ),
            at: 0
        )

        if recentActivities.count > 20 {
            recentActivities = Array(recentActivities.prefix(20))
        }
    }

    private func addDuplicateScanActivity() {
        let count = duplicateService.progress.duplicatesFound
        let subtitle = count == 1 ? "1 duplicate group found" : "\(count) duplicate groups found"

        recentActivities.insert(
            RecentActivityItem(
                id: UUID(),
                title: "Duplicate scan finished",
                subtitle: subtitle,
                timestamp: Date(),
                icon: "doc.on.doc.fill"
            ),
            at: 0
        )

        if recentActivities.count > 20 {
            recentActivities = Array(recentActivities.prefix(20))
        }
    }
}
