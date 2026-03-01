// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Main sync interface - shows different content based on SyncService.state
struct SyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @EnvironmentObject var profileManager: SyncProfileManager

    @EnvironmentObject var configManager: LLMConfigManager

    @State private var swapRotation: Double = 0
    @State private var showProfilesSheet = false
    @State private var showFilterEditor: Bool = false
    @State private var showConfetti = false
    @State private var showParallelInfo = false
    @State private var showBuddyPanel = true
    @State private var buddyInput = ""
    @StateObject private var buddyChatService = SetupBuddyChatService(screen: .sync)

    var body: some View {
        Group {
            if syncService.state == .previewing {
                SyncPreviewView()
                    .padding(AppTheme.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            AIChatToggleButton(isVisible: $showBuddyPanel)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.top, AppTheme.Spacing.small)

                        ScrollView {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                                switch syncService.state {
                                case .idle:
                                    idleContent
                                case .comparing:
                                    comparingContent
                                case .syncing, .paused:
                                    SyncProgressView()
                                case .completed:
                                    completedContent
                                case .failed:
                                    failedContent
                                case .previewing:
                                    EmptyView()
                                }
                            }
                            .padding(AppTheme.Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showBuddyPanel {
                        AIChatPanelView(
                            title: "DriveSyncAI Buddy",
                            placeholder: "Ask about sync setup...",
                            messages: buddyChatService.messages,
                            input: $buddyInput,
                            isLoading: buddyChatService.isLoading,
                            quickActions: [
                                "Mirror vs Update?",
                                "Should I use parallel?",
                                "How do filters work?",
                            ],
                            onSend: { sendBuddyMessage() },
                            onClose: { showBuddyPanel = false }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showBuddyPanel)
                .onAppear { buddyChatService.addWelcomeMessage() }
            }
        }
        .background(Color.dsBackground)
        .overlay {
            ConfettiView(isActive: $showConfetti)
        }
        .onChange(of: syncService.state) { oldState, newState in
            if oldState == .syncing && newState == .completed {
                showConfetti = true
            }
        }
    }

    private func sendBuddyMessage() {
        let text = buddyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !buddyChatService.isLoading else { return }
        buddyInput = ""
        Task {
            await buddyChatService.send(
                userText: text,
                drives: volumeMonitor.mountedVolumes,
                configManager: configManager
            )
        }
    }

    // MARK: - Idle State

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sourceTargetSection
            directionSection
            parallelToggleSection

            HStack(spacing: AppTheme.Spacing.medium) {
                GlassButton("Filters", icon: "line.3.horizontal.decrease.circle", style: .secondary) {
                    showFilterEditor = true
                }
                GlassButton("Profiles", icon: "folder.badge.gearshape", style: .secondary) {
                    showProfilesSheet = true
                }
                compareButton
            }
        }
        .sheet(isPresented: $showProfilesSheet) {
            SyncProfilesView(profileManager: profileManager)
        }
        .sheet(isPresented: $showFilterEditor) {
            FilterEditorView(rules: $syncService.filterRules)
                .frame(minWidth: 500, minHeight: 500)
        }
    }

    private var sourceTargetSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Source & Target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                HStack(spacing: AppTheme.Spacing.medium) {
                    DrivePickerView(
                        volumeMonitor: volumeMonitor,
                        selectedURL: Binding(
                            get: { syncService.sourceURL },
                            set: { syncService.sourceURL = $0 }
                        ),
                        allowCustomPath: true
                    )
                    .frame(maxWidth: .infinity)

                    swapButton

                    DrivePickerView(
                        volumeMonitor: volumeMonitor,
                        selectedURL: Binding(
                            get: { syncService.targetURL },
                            set: { syncService.targetURL = $0 }
                        ),
                        allowCustomPath: true
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 56)
            }
        }
    }

    private var swapButton: some View {
        Button {
            withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
                swapRotation += 180
                swapSourceAndTarget()
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.dsAction)
                .symbolRenderingMode(.hierarchical)
                .rotationEffect(.degrees(swapRotation))
        }
        .buttonStyle(.plain)
        .help("Swap source and target")
    }

    private func swapSourceAndTarget() {
        let src = syncService.sourceURL
        let tgt = syncService.targetURL
        syncService.sourceURL = tgt
        syncService.targetURL = src
    }

    private var directionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Sync Direction")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                Picker("", selection: Binding(
                    get: { syncService.direction },
                    set: { syncService.direction = $0 }
                )) {
                    Text("Mirror →").tag(SyncDirection.oneWayMirror)
                    Text("Update →").tag(SyncDirection.oneWayUpdate)
                    Text("Sync ↔").tag(SyncDirection.bidirectional)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var compareButton: some View {
        GlassButton("Compare", icon: "arrow.triangle.2.circlepath", isDisabled: syncService.sourceURL == nil || syncService.targetURL == nil) {
            Task { await syncService.compare() }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    // MARK: - Parallel Toggle

    private var parallelToggleSection: some View {
        GlassCard {
            HStack(spacing: AppTheme.Spacing.medium) {
                Toggle(isOn: $syncService.parallelIOEnabled) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Text("Parallel File Operations")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.dsPrimaryText)

                        Button {
                            showParallelInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsAction)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showParallelInfo, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                                Text("Parallel File Operations")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.dsPrimaryText)

                                Text("When enabled, multiple files are copied simultaneously using \(ProcessInfo.processInfo.processorCount) CPU cores. The concurrency is automatically tuned based on your drive type:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.dsSecondaryText)

                                VStack(alignment: .leading, spacing: 4) {
                                    parallelInfoRow("USB 2.0", limit: "2 concurrent")
                                    parallelInfoRow("USB 3.x", limit: "4 concurrent")
                                    parallelInfoRow("Thunderbolt", limit: "6 concurrent")
                                    parallelInfoRow("NVMe / Internal", limit: "8 concurrent")
                                }

                                Text("Recommended for large syncs with many small files. For drives with slow I/O (USB 2.0), sequential mode may be more reliable.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.dsTertiaryText)
                            }
                            .padding(AppTheme.Spacing.large)
                            .frame(width: 300)
                        }
                    }
                }
                .toggleStyle(.switch)

                Spacer()
            }
        }
    }

    private func parallelInfoRow(_ drive: String, limit: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("\u{2022}")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsAction)
            Text(drive)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsPrimaryText)
                .frame(width: 100, alignment: .leading)
            Text(limit)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    // MARK: - Comparing State

    private var comparingContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                AnimatedProgressBar(value: 0, label: "Comparing directories...", detailText: nil, isIndeterminate: true)
                    .frame(height: 48)

                HStack {
                    Text("Scanning and comparing files…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsSecondaryText)
                    Spacer()
                    GlassButton("Cancel", icon: "xmark", style: .secondary) {
                        syncService.cancel()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Completed State

    private var completedContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.dsSuccess)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync completed")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.dsPrimaryText)

                        Text("\(syncService.progress.completedFiles) files synced · \(ByteCountFormatter.string(fromByteCount: Int64(syncService.progress.transferredBytes), countStyle: .file)) transferred")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)
                    }

                    Spacer()

                    GlassButton("New Sync", icon: "arrow.counterclockwise", style: .secondary) {
                        syncService.state = .idle
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Failed State

    private var failedContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.dsDestructive)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync failed")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.dsPrimaryText)

                        if let firstError = syncService.errors.first {
                            Text(firstError.message)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                    }

                    Spacer()
                }

                if syncService.errors.count > 1 {
                    Text("\(syncService.errors.count) errors occurred")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsTertiaryText)
                }

                GlassButton("Try Again", icon: "arrow.clockwise", style: .secondary) {
                    syncService.state = .idle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
