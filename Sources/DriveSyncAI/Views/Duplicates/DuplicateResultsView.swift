// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Results display for duplicate scan with filters, smart select, and move actions.
struct DuplicateResultsView: View {
    @EnvironmentObject var duplicateService: DuplicateFinderService
    @EnvironmentObject var configManager: LLMConfigManager
    @StateObject private var chatService = DuplicateChatService()

    var onSuccessfulMove: (() -> Void)? = nil

    @State private var categoryFilter: DuplicateFinderService.FileCategory? = nil
    @State private var sortOption: SortOption = .bySizeDesc
    @State private var showUndoAfterMove = false
    @State private var selectedTab: ResultsTab = .exact
    @State private var previewFile: FileInfo?
    @State private var showPreview = false
    @State private var showChatPanel = true
    @State private var chatInput = ""
    @AppStorage("hasAcceptedAIDisclaimer") private var hasAcceptedAIDisclaimer = false

    enum ResultsTab: String, CaseIterable {
        case exact = "Exact Duplicates"
        case similar = "Similar Files"
    }

    enum SortOption: String, CaseIterable {
        case bySizeDesc = "Size (largest first)"
        case byName = "Name"
        case byGroupCount = "Group size"

        var label: String { rawValue }
    }

    private var filteredAndSortedGroups: [DuplicateGroup] {
        var groups = duplicateService.duplicateGroups
        if let cat = categoryFilter {
            groups = groups.filter { group in
                guard let first = group.files.first else { return false }
                let ext = (first.fileInfo.name as NSString).pathExtension.lowercased()
                return DuplicateFinderService.FileCategory.category(for: ext) == cat
            }
        }
        switch sortOption {
        case .bySizeDesc:
            groups.sort { $0.wastedSpace > $1.wastedSpace }
        case .byName:
            groups.sort { ($0.files.first?.fileInfo.name ?? "") < ($1.files.first?.fileInfo.name ?? "") }
        case .byGroupCount:
            groups.sort { $0.files.count > $1.files.count }
        }
        return groups
    }

    private var totalDuplicates: Int {
        duplicateService.duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }

    private var totalWasted: UInt64 {
        duplicateService.duplicateGroups.reduce(0) { $0 + $1.wastedSpace }
    }

    private var formattedTotalWasted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalWasted), countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    tabPicker
                    Spacer()
                    AIChatToggleButton(isVisible: $showChatPanel)
                        .padding(.trailing, AppTheme.Spacing.xl)
                        .padding(.top, AppTheme.Spacing.medium)
                }

                ZStack(alignment: .trailing) {
                    Group {
                        switch selectedTab {
                        case .exact:
                            ScrollView {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                                    headerSection
                                    smartSelectSection
                                    filterSortSection
                                    groupsList
                                    footerSection
                                }
                                .padding(AppTheme.Spacing.xl)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        case .similar:
                            SimilarFilesView(
                                groups: $duplicateService.similarGroups,
                                onToggle: { groupId, fileId in duplicateService.toggleSimilarFile(groupId: groupId, fileId: fileId) },
                                onMoveSelected: {
                                    Task {
                                        let moved = await duplicateService.moveSimilarFiles()
                                        if moved > 0 { onSuccessfulMove?() }
                                    }
                                },
                                onFileClick: { file in
                                    previewFile = file
                                    showPreview = true
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showPreview, let file = previewFile {
                        FilePreviewPanel(fileInfo: file, isVisible: $showPreview)
                            .transition(.move(edge: .trailing))
                            .zIndex(10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)

            if showChatPanel {
                duplicateChatPanel
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showChatPanel)
        .onAppear {
            let wastedStr = formattedTotalWasted
            chatService.addWelcomeMessage(
                groupCount: duplicateService.duplicateGroups.count,
                wastedSpace: wastedStr
            )
        }
    }

    // MARK: - Duplicate Chat Panel

    private var duplicateChatPanel: some View {
        AIChatPanelView(
            title: "DriveSyncAI Buddy",
            placeholder: "Try: \"keep the newest copy\"...",
            messages: chatService.messages,
            input: $chatInput,
            isLoading: chatService.isLoading,
            quickActions: [
                "Keep newest copies",
                "Select photos only",
                "Select files > 10MB",
            ],
            onSend: { sendDuplicateChatMessage() },
            onClose: { showChatPanel = false },
            isDisclaimerAccepted: hasAcceptedAIDisclaimer,
            pendingContent: {
                if let pending = chatService.pendingResult, pending.hasChanges {
                    duplicateApplyBanner(result: pending)
                }
            },
            extraContent: { EmptyView() }
        )
    }

    private func sendDuplicateChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        chatInput = ""
        Task {
            await chatService.send(
                userText: text,
                groups: duplicateService.duplicateGroups,
                configManager: configManager
            )
        }
    }

    private func duplicateApplyBanner(result: DuplicateRefinementResult) -> some View {
        VStack(spacing: 6) {
            Text(result.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsPrimaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Apply") {
                    applyDuplicateChanges(result.selectionChanges)
                    chatService.clearPendingResult()
                    chatService.messages.append(
                        OrganizationChatMessage(role: "system", text: "Changes applied.", isStatusMessage: true)
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)

                Button("Dismiss") {
                    chatService.clearPendingResult()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
    }

    private func applyDuplicateChanges(_ changes: [DuplicateSelectionChange]) {
        for change in changes {
            switch change.action {
            case "selectAll":
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        duplicateService.duplicateGroups[gi].files[fi].isSelected = true
                    }
                }
            case "deselectAll":
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        duplicateService.duplicateGroups[gi].files[fi].isSelected = false
                    }
                }
            case "smartSelectKeepNewest":
                duplicateService.applySmartSelect(.keepNewest)
            case "smartSelectKeepOldest":
                duplicateService.applySmartSelect(.keepOldest)
            case "smartSelectKeepShortestPath":
                duplicateService.applySmartSelect(.keepShortestPath)
            case "selectByCategory":
                guard let target = change.target else { continue }
                let cat = DuplicateFinderService.FileCategory.allCases.first { $0.rawValue == target }
                guard let cat else { continue }
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        let ext = (duplicateService.duplicateGroups[gi].files[fi].fileInfo.name as NSString).pathExtension
                        if DuplicateFinderService.FileCategory.category(for: ext) == cat {
                            duplicateService.duplicateGroups[gi].files[fi].isSelected = true
                        }
                    }
                }
            case "deselectByCategory":
                guard let target = change.target else { continue }
                let cat = DuplicateFinderService.FileCategory.allCases.first { $0.rawValue == target }
                guard let cat else { continue }
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        let ext = (duplicateService.duplicateGroups[gi].files[fi].fileInfo.name as NSString).pathExtension
                        if DuplicateFinderService.FileCategory.category(for: ext) == cat {
                            duplicateService.duplicateGroups[gi].files[fi].isSelected = false
                        }
                    }
                }
            case "selectByFolder":
                guard let target = change.target else { continue }
                let prefix = target.hasSuffix("/") ? target : target + "/"
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        let path = duplicateService.duplicateGroups[gi].files[fi].fileInfo.relativePath
                        if path.hasPrefix(prefix) || path.hasPrefix(target) {
                            duplicateService.duplicateGroups[gi].files[fi].isSelected = true
                        }
                    }
                }
            case "deselectByFolder":
                guard let target = change.target else { continue }
                let prefix = target.hasSuffix("/") ? target : target + "/"
                for gi in duplicateService.duplicateGroups.indices {
                    for fi in duplicateService.duplicateGroups[gi].files.indices {
                        let path = duplicateService.duplicateGroups[gi].files[fi].fileInfo.relativePath
                        if path.hasPrefix(prefix) || path.hasPrefix(target) {
                            duplicateService.duplicateGroups[gi].files[fi].isSelected = false
                        }
                    }
                }
            case "selectByMinSize":
                guard let threshold = change.threshold else { continue }
                let bytes = parseByteThreshold(threshold)
                for gi in duplicateService.duplicateGroups.indices {
                    let fileSize = duplicateService.duplicateGroups[gi].files.first?.fileInfo.size ?? 0
                    if fileSize >= bytes {
                        for fi in duplicateService.duplicateGroups[gi].files.indices {
                            duplicateService.duplicateGroups[gi].files[fi].isSelected = true
                        }
                    }
                }
            default:
                break
            }
        }
    }

    private func parseByteThreshold(_ str: String) -> UInt64 {
        let cleaned = str.lowercased().trimmingCharacters(in: .whitespaces)
        let multipliers: [(String, UInt64)] = [
            ("tb", 1_000_000_000_000),
            ("gb", 1_000_000_000),
            ("mb", 1_000_000),
            ("kb", 1_000),
        ]
        for (suffix, mult) in multipliers {
            if cleaned.hasSuffix(suffix) {
                let numStr = cleaned.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if let val = Double(numStr) { return UInt64(val * Double(mult)) }
            }
        }
        return UInt64(cleaned) ?? 0
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ResultsTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.top, AppTheme.Spacing.medium)
        .padding(.bottom, AppTheme.Spacing.small)
    }

    private var headerSection: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("\(totalDuplicates) duplicates found in \(duplicateService.duplicateGroups.count) groups")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)
                    Text("Potential savings: \(formattedTotalWasted)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                Spacer()
                GlassButton("New Scan", icon: "arrow.counterclockwise", style: .secondary) {
                    duplicateService.state = .idle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var smartSelectSection: some View {
        GlassCard {
            HStack(spacing: AppTheme.Spacing.medium) {
                Text("Smart Select")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsPrimaryText)

                Picker("", selection: Binding(
                    get: { duplicateService.selectStrategy },
                    set: { duplicateService.selectStrategy = $0 }
                )) {
                    ForEach(SmartSelectStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                GlassButton("Apply to All", icon: "checkmark.circle", style: .secondary) {
                    duplicateService.applySmartSelect(duplicateService.selectStrategy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filterSortSection: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            HStack(spacing: AppTheme.Spacing.small) {
                Text("Category")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                Picker("", selection: $categoryFilter) {
                    Text("All").tag(nil as DuplicateFinderService.FileCategory?)
                    ForEach(DuplicateFinderService.FileCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat as DuplicateFinderService.FileCategory?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            HStack(spacing: AppTheme.Spacing.small) {
                Text("Sort")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                Picker("", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
        }
    }

    private var groupsList: some View {
        LazyVStack(spacing: AppTheme.Spacing.medium) {
            ForEach(filteredAndSortedGroups) { group in
                DuplicateGroupView(group: group, onToggle: { fileId in
                    duplicateService.toggleFile(groupId: group.id, fileId: fileId)
                }, onFileClick: { file in
                    previewFile = file
                    showPreview = true
                })
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: AppTheme.Spacing.large) {
                Text("Selected: \(duplicateService.selectedCount) files (\(duplicateService.formattedSelectedSize))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)

                Spacer()

                GlassButton("Move to Duplicates Folder", icon: "folder.badge.arrow.down", isDisabled: !duplicateService.canMoveDuplicates) {
                    Task {
                        let moved = await duplicateService.moveDuplicates()
                        showUndoAfterMove = moved > 0
                        if moved > 0 { onSuccessfulMove?() }
                    }
                }

                if showUndoAfterMove {
                    GlassButton("Undo", icon: "arrow.uturn.backward", style: .secondary) {
                        Task {
                            _ = await duplicateService.undoLastMove()
                            showUndoAfterMove = false
                        }
                    }
                }
            }

            if !duplicateService.errors.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    ForEach(duplicateService.errors) { err in
                        HStack(spacing: AppTheme.Spacing.small) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.dsDestructive)
                            Text(err.message)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.dsDestructive)
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
                .background(Color.dsDestructive.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
            }
        }
    }
}
