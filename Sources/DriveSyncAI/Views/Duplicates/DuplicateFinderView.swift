// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Main duplicate finder container with scan config, progress, and results.
struct DuplicateFinderView: View {
    @EnvironmentObject var duplicateService: DuplicateFinderService
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @EnvironmentObject var configManager: LLMConfigManager

    @State private var showConfetti = false
    @State private var showParallelInfo = false
    @State private var showBuddyPanel = true
    @State private var buddyInput = ""
    @StateObject private var buddyChatService = SetupBuddyChatService(screen: .duplicates)

    private var targetDriveURLBinding: Binding<URL?> {
        Binding(
            get: { duplicateService.targetDrive?.url },
            set: { url in
                if let url = url {
                    if let drive = volumeMonitor.mountedVolumes.first(where: { $0.url == url }) {
                        duplicateService.targetDrive = drive
                    } else {
                        let info = DriveInfo(
                            id: UUID(),
                            url: url,
                            name: url.lastPathComponent,
                            totalCapacity: 0,
                            availableCapacity: 0,
                            connectionType: .unknown,
                            isRemovable: false,
                            volumeFormat: "—",
                            isCaseSensitive: false
                        )
                        duplicateService.targetDrive = info
                    }
                } else {
                    duplicateService.targetDrive = nil
                }
            }
        )
    }

    private var showBuddyOverlay: Bool {
        duplicateService.state == .idle || duplicateService.state == .scanning || duplicateService.state == .moving
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if showBuddyOverlay {
                    HStack {
                        Spacer()
                        AIChatToggleButton(isVisible: $showBuddyPanel)
                    }
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.top, AppTheme.Spacing.small)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        switch duplicateService.state {
                        case .idle:
                            scanConfigSection
                        case .scanning:
                            scanningSection
                        case .results, .completed:
                            DuplicateResultsView(onSuccessfulMove: { showConfetti = true })
                        case .moving:
                            movingSection
                        }
                    }
                    .padding(AppTheme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showBuddyOverlay && showBuddyPanel {
                AIChatPanelView(
                    title: "DriveSyncAI Buddy",
                    placeholder: "Ask about duplicate scanning...",
                    messages: buddyChatService.messages,
                    input: $buddyInput,
                    isLoading: buddyChatService.isLoading,
                    quickActions: [
                        "Which scan mode?",
                        "Smart vs Deep?",
                        "What do categories filter?",
                    ],
                    onSend: { sendBuddyMessage() },
                    onClose: { showBuddyPanel = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showBuddyPanel)
        .background(Color.dsBackground)
        .overlay {
            ConfettiView(isActive: $showConfetti)
        }
        .onAppear { buddyChatService.addWelcomeMessage() }
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

    // MARK: - Scan Config (Idle)

    private var scanConfigSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    Text("Target Drive")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    DrivePickerView(
                        volumeMonitor: volumeMonitor,
                        selectedURL: targetDriveURLBinding,
                        allowCustomPath: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Scan Mode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(ScanMode.allCases, id: \.self) { mode in
                            scanModeRow(mode)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Categories")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: AppTheme.Spacing.small) {
                        ForEach(DuplicateFinderService.FileCategory.allCases, id: \.self) { cat in
                            categoryToggle(cat)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Exclusions")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    HStack(spacing: AppTheme.Spacing.xl) {
                        Toggle("Exclude system files", isOn: $duplicateService.excludeSystemFiles)
                            .toggleStyle(.switch)
                        Toggle("Exclude hidden files", isOn: $duplicateService.excludeHiddenFiles)
                            .toggleStyle(.switch)
                    }
                }
            }

            parallelToggleSection

            GlassButton("Start Scan", icon: "magnifyingglass", isDisabled: duplicateService.targetDrive == nil) {
                Task { await duplicateService.startScan() }
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func scanModeRow(_ mode: ScanMode) -> some View {
        let isSelected = duplicateService.scanMode == mode
        let (title, desc) = scanModeDescription(mode)
        return Button {
            duplicateService.scanMode = mode
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.dsAction : Color.dsSecondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                Spacer()
            }
            .padding(AppTheme.Spacing.medium)
            .background(isSelected ? Color.dsAction.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func scanModeDescription(_ mode: ScanMode) -> (String, String) {
        switch mode {
        case .quick:
            return ("Quick", "Match by name + size only. Fastest.")
        case .smart:
            return ("Smart", "Partial hash first, then full hash. Balanced.")
        case .deep:
            return ("Deep", "Full SHA256 for all. Most accurate.")
        }
    }

    private func categoryToggle(_ category: DuplicateFinderService.FileCategory) -> some View {
        let isIncluded = duplicateService.includedCategories.contains(category)
        return Button {
            if isIncluded {
                duplicateService.includedCategories.remove(category)
            } else {
                duplicateService.includedCategories.insert(category)
            }
        } label: {
            Text(category.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isIncluded ? Color.dsPrimaryText : Color.dsSecondaryText)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(isIncluded ? Color.dsAction.opacity(0.15) : Color.dsSecondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parallel Toggle

    private var parallelToggleSection: some View {
        GlassCard {
            HStack(spacing: AppTheme.Spacing.medium) {
                Toggle(isOn: $duplicateService.parallelIOEnabled) {
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

                                Text("When enabled, duplicate files are moved simultaneously instead of one at a time. Concurrency is tuned by drive type:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.dsSecondaryText)

                                VStack(alignment: .leading, spacing: 4) {
                                    dupParallelInfoRow("USB 2.0", limit: "2 concurrent")
                                    dupParallelInfoRow("USB 3.x", limit: "4 concurrent")
                                    dupParallelInfoRow("Thunderbolt", limit: "6 concurrent")
                                    dupParallelInfoRow("NVMe / Internal", limit: "8 concurrent")
                                }

                                Text("Hashing (during scan) always uses parallel processing regardless of this setting.")
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

    private func dupParallelInfoRow(_ drive: String, limit: String) -> some View {
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

    // MARK: - Scanning State

    private var scanningSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                    RadarScanView()
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Text(duplicateService.progress.phase)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.dsPrimaryText)

                        Text("\(duplicateService.progress.processedFiles) files scanned")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)

                        Text("Duplicates found: \(duplicateService.progress.duplicatesFound)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)

                        Text("Space recoverable: \(ByteCountFormatter.string(fromByteCount: Int64(duplicateService.progress.spaceRecoverable), countStyle: .file))")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GlassButton("Cancel", icon: "xmark.circle", style: .secondary) {
                        duplicateService.cancelScan()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AnimatedProgressBar(
                    value: duplicateService.progress.percentage / 100,
                    label: nil,
                    detailText: duplicateService.progress.currentFile.isEmpty ? nil : duplicateService.progress.currentFile,
                    isIndeterminate: duplicateService.progress.totalFiles == 0
                )
                .frame(height: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Moving State

    private var movingSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    AnimatedProgressBar(value: 0, label: "Moving duplicates...", detailText: nil, isIndeterminate: true)
                        .frame(height: 48)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
