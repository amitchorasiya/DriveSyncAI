// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct SyncPreviewView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var configManager: LLMConfigManager
    @StateObject private var syncChatService = SyncChatService()

    @State private var filterType: SyncActionType?
    @State private var expandedConflictIds: Set<UUID> = []
    @State private var showConflictResolutionSheet = false

    // Tree state
    @State private var treeRoots: [SyncTreeNode] = []
    @State private var expandedPaths: Set<String> = []
    @State private var activeFileTypes: Set<FileTypeCategory> = Set(FileTypeCategory.allCases)
    @State private var isTreeLoading = true

    // Cached derived state (refreshed explicitly, not recomputed per render)
    @State private var cachedVisibleNodes: [SyncTreeNode] = []
    @State private var cachedFileTypeCounts: [FileTypeCategory: Int] = [:]
    @State private var cachedActiveFileCount: Int = 0
    @State private var cachedFilteredCount: Int = 0

    // Chat state
    @State private var showChatPanel = true
    @State private var chatInput = ""

    // Undo state
    @State private var undoSnapshot: UndoSnapshot?
    @State private var showDirectionConfirm = false
    @State private var pendingDirectionChange: String?

    private var filteredActions: [SyncAction] {
        guard let filter = filterType else { return syncService.actions }
        return syncService.actions.filter { $0.actionType == filter }
    }

    // Cached lookup — rebuilt explicitly, not per render
    @State private var cachedActionLookup: [UUID: SyncAction] = [:]

    private struct ActionStats {
        var createCount = 0
        var updateCount = 0
        var deleteCount = 0
        var conflictCount = 0
        var skipCount = 0
        var spaceRequired: UInt64 = 0
        var hasSelected = false
    }

    private var stats: ActionStats {
        var s = ActionStats()
        for action in syncService.actions {
            switch action.actionType {
            case .create: s.createCount += 1
            case .update: s.updateCount += 1
            case .delete: s.deleteCount += 1
            case .conflict: s.conflictCount += 1
            case .skip: s.skipCount += 1
            }
            if action.isSelected {
                s.hasSelected = true
                if action.actionType == .create || action.actionType == .update {
                    s.spaceRequired += action.fileSize
                }
            }
        }
        return s
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: AppTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        summaryBar
                        toolbar
                    }
                    .frame(maxWidth: .infinity)
                    AIChatToggleButton(isVisible: $showChatPanel)
                }
                .padding(.bottom, AppTheme.Spacing.medium)

                HStack(spacing: AppTheme.Spacing.medium) {
                    filterSidebar
                    treeContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showChatPanel {
                chatPanel
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showChatPanel)
        .sheet(isPresented: $showConflictResolutionSheet) {
            ConflictResolutionView()
                .environmentObject(syncService)
        }
        .alert("Change Sync Direction?", isPresented: $showDirectionConfirm) {
            Button("Change & Re-compare", role: .destructive) {
                applyDirectionChange()
            }
            Button("Cancel", role: .cancel) {
                pendingDirectionChange = nil
            }
        } message: {
            Text("Changing direction will re-compare the drives. Current selections may change.")
        }
        .onAppear {
            refreshActionLookup()
            refreshFileTypeCounts()
            rebuildTreeAsync()
            let totalSize = ByteCountFormatter.string(fromByteCount: Int64(syncService.actions.reduce(UInt64(0)) { $0 + $1.fileSize }), countStyle: .file)
            syncChatService.addWelcomeMessage(actionCount: syncService.actions.count, totalSize: totalSize)
        }
        .onReceive(syncService.$actions) { _ in
            refreshActionLookup()
        }
        .onChange(of: syncService.actions.count) { _, _ in
            refreshFileTypeCounts()
            rebuildTreeAsync()
        }
        .onChange(of: filterType) { _, _ in
            refreshFileTypeCounts()
            rebuildTreeAsync()
        }
        .onChange(of: activeFileTypes) { _, _ in
            refreshActiveFileCount()
        }
    }

    private func rebuildTreeAsync() {
        isTreeLoading = true
        let actions = filteredActions
        Task {
            let roots = await SyncTreeBuilder.buildTreeOffMainThread(from: actions)
            treeRoots = roots
            refreshVisibleNodes()
            isTreeLoading = false
        }
    }

    private func refreshActionLookup() {
        var lookup: [UUID: SyncAction] = [:]
        lookup.reserveCapacity(syncService.actions.count)
        for action in syncService.actions {
            lookup[action.id] = action
        }
        cachedActionLookup = lookup
    }

    private func refreshVisibleNodes() {
        cachedVisibleNodes = SyncTreeBuilder.flattenVisible(roots: treeRoots, expandedPaths: expandedPaths)
    }

    private func refreshFileTypeCounts() {
        let filtered = filteredActions
        cachedFilteredCount = filtered.count
        var counts: [FileTypeCategory: Int] = [:]
        for cat in FileTypeCategory.allCases { counts[cat] = 0 }
        var activeCount = 0
        for action in filtered {
            let ext = (action.relativePath as NSString).pathExtension
            let cat = FileTypeCategory.category(for: ext)
            counts[cat, default: 0] += 1
            if activeFileTypes.contains(cat) { activeCount += 1 }
        }
        cachedFileTypeCounts = counts
        cachedActiveFileCount = activeCount
    }

    private func refreshActiveFileCount() {
        let filtered = filteredActions
        cachedActiveFileCount = filtered.reduce(0) { count, action in
            let ext = (action.relativePath as NSString).pathExtension
            return activeFileTypes.contains(FileTypeCategory.category(for: ext)) ? count + 1 : count
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let s = stats
        return HStack(spacing: 2) {
            if s.createCount > 0 {
                summarySegment(count: s.createCount, color: Color.dsSuccess, label: "Create")
            }
            if s.updateCount > 0 {
                summarySegment(count: s.updateCount, color: Color.dsAction, label: "Update")
            }
            if s.deleteCount > 0 {
                summarySegment(count: s.deleteCount, color: Color.dsDestructive, label: "Delete")
            }
            if s.conflictCount > 0 {
                summarySegment(count: s.conflictCount, color: Color.dsWarning, label: "Conflict")
            }
            if s.skipCount > 0 {
                summarySegment(count: s.skipCount, color: Color.dsSecondaryText, label: "Skip")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous))
        .frame(height: 28)
    }

    private func summarySegment(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.2))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            GlassButton("Select All", icon: "checkmark.circle", style: .secondary) {
                syncService.selectAll(true)
            }
            GlassButton("Deselect All", icon: "circle", style: .secondary) {
                syncService.selectAll(false)
            }

            if stats.conflictCount > 0 {
                GlassButton("Resolve Conflicts (\(stats.conflictCount))", icon: "exclamationmark.triangle.fill", style: .secondary) {
                    showConflictResolutionSheet = true
                }
            }

            Spacer()

            Button {
                withAnimation(AppTheme.Animation.quickFade) {
                    expandAllFolders()
                }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsSecondaryText)
            .help("Expand all folders")

            Button {
                withAnimation(AppTheme.Animation.quickFade) {
                    expandedPaths.removeAll()
                    refreshVisibleNodes()
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsSecondaryText)
            .help("Collapse all folders")

            Menu {
                Button("All") { filterType = nil }
                Button("Creates only") { filterType = .create }
                Button("Updates only") { filterType = .update }
                Button("Deletes only") { filterType = .delete }
                Button("Conflicts only") { filterType = .conflict }
            } label: {
                HStack(spacing: AppTheme.Spacing.small) {
                    Text("Filter: \(filterLabel)")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.dsPrimaryText)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                        .fill(Color.dsSecondaryFill)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var filterLabel: String {
        switch filterType {
        case .none: return "All"
        case .create: return "Creates"
        case .update: return "Updates"
        case .delete: return "Deletes"
        case .conflict: return "Conflicts"
        case .skip: return "Skips"
        }
    }

    // MARK: - Filter Sidebar

    private var filterSidebar: some View {
        GlassCard(padding: AppTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("File Types")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                    .padding(.bottom, 2)

                ForEach(FileTypeCategory.allCases) { category in
                    fileTypeCategoryRow(category)
                }

                Divider()
                    .padding(.vertical, AppTheme.Spacing.small)

                Text("Showing \(cachedActiveFileCount) of \(cachedFilteredCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
        .frame(width: 180)
    }

    private func fileTypeCategoryRow(_ category: FileTypeCategory) -> some View {
        let count = cachedFileTypeCounts[category] ?? 0
        return HStack(spacing: AppTheme.Spacing.small) {
            Toggle("", isOn: Binding(
                get: { activeFileTypes.contains(category) },
                set: { isOn in
                    withAnimation(AppTheme.Animation.quickFade) {
                        if isOn { activeFileTypes.insert(category) }
                        else { activeFileTypes.remove(category) }
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: category.icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 16)

            Text(category.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsPrimaryText)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.dsSecondaryFill, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tree Content

    private var treeContent: some View {
        GlassCard(padding: 0) {
            if isTreeLoading {
                VStack {
                    Spacer()
                    ProgressView("Building file tree...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsSecondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let nodes = cachedVisibleNodes
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                            treeRow(for: node)

                            if index < nodes.count - 1 {
                                Divider()
                                    .background(Color.dsSeparator)
                                    .padding(.leading, CGFloat(node.depth + 1) * 20 + 52)
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                }
            }
        }
    }

    @ViewBuilder
    private func treeRow(for node: SyncTreeNode) -> some View {
        let dimmed = SyncTreeBuilder.isNodeDimmed(node, activeFileTypes: activeFileTypes)

        if node.isFolder {
            folderRow(node: node, dimmed: dimmed)
        } else if let actionId = node.actionId, let action = cachedActionLookup[actionId] {
            fileRow(node: node, action: action, dimmed: dimmed)
        }
    }

    // MARK: - Folder Row

    private func folderRow(node: SyncTreeNode, dimmed: Bool) -> some View {
        let isExpanded = expandedPaths.contains(node.path)
        let selState = SyncTreeBuilder.folderSelectionState(for: node, lookup: cachedActionLookup)

        return HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 12)

            folderCheckbox(selState: selState, node: node)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsAction)

            Text(node.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
                .lineLimit(1)

            Spacer()

            Text("\(node.cachedFileCount) \(node.cachedFileCount == 1 ? "file" : "files")")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTertiaryText)

            Text(ByteCountFormatter.string(fromByteCount: Int64(node.cachedTotalSize), countStyle: .file))
                .font(.system(size: 11))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.leading, CGFloat(node.depth) * 20 + AppTheme.Spacing.medium)
        .padding(.trailing, AppTheme.Spacing.medium)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .opacity(dimmed ? 0.35 : 1.0)
        .onTapGesture {
            withAnimation(AppTheme.Animation.quickFade) {
                if expandedPaths.contains(node.path) {
                    collapseRecursive(node)
                } else {
                    expandedPaths.insert(node.path)
                }
                refreshVisibleNodes()
            }
        }
    }

    @ViewBuilder
    private func folderCheckbox(selState: FolderSelectionState, node: SyncTreeNode) -> some View {
        Button {
            toggleFolderSelection(node)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(selState == .none ? Color.dsSecondaryText : Color.dsAction, lineWidth: 1.5)
                    .frame(width: 14, height: 14)

                switch selState {
                case .all:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.dsAction)
                        .frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                case .partial:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.dsAction.opacity(0.5))
                        .frame(width: 14, height: 14)
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                case .none:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Row

    private func fileRow(node: SyncTreeNode, action: SyncAction, dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.medium) {
                Toggle("", isOn: Binding(
                    get: { action.isSelected },
                    set: { _ in syncService.toggleAction(action.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                ActionBadgeView(actionType: action.actionType)

                if let url = (action.sourceFile ?? action.targetFile)?.url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }

                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(action.formattedSize)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
                    .frame(width: 60, alignment: .trailing)

                if action.actionType == .conflict {
                    Button {
                        withAnimation(AppTheme.Animation.quickFade) {
                            if expandedConflictIds.contains(action.id) {
                                expandedConflictIds.remove(action.id)
                            } else {
                                expandedConflictIds.insert(action.id)
                            }
                        }
                    } label: {
                        Image(systemName: expandedConflictIds.contains(action.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, CGFloat(node.depth) * 20 + AppTheme.Spacing.medium)
            .padding(.trailing, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.35 : 1.0)
            .onTapGesture {
                if action.actionType == .conflict {
                    showConflictResolutionSheet = true
                } else {
                    syncService.toggleAction(action.id)
                }
            }

            if action.actionType == .conflict && expandedConflictIds.contains(action.id),
               let src = action.sourceFile, let tgt = action.targetFile {
                conflictResolutionPanel(src: src, tgt: tgt, action: action)
            }
        }
    }

    private func conflictResolutionPanel(src: FileInfo, tgt: FileInfo, action: SyncAction) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Divider()
                .background(Color.dsSeparator)
                .padding(.leading, 52)

            HStack(spacing: AppTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source: \(formattedDate(src.modificationDate))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaryText)
                    Text(src.formattedSize)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Target: \(formattedDate(tgt.modificationDate))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaryText)
                    Text(tgt.formattedSize)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiaryText)
                }

                Spacer()

                HStack(spacing: AppTheme.Spacing.small) {
                    conflictButton("Keep Source", strategy: .keepSource, actionId: action.id)
                    conflictButton("Keep Target", strategy: .keepTarget, actionId: action.id)
                    conflictButton("Keep Newer", strategy: .keepNewer, actionId: action.id)
                    conflictButton("Keep Both", strategy: .keepBoth, actionId: action.id)
                    conflictButton("Skip", strategy: .skip, actionId: action.id)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(Color.dsSecondaryFill.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous))
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.bottom, AppTheme.Spacing.small)
        }
    }

    private func conflictButton(_ title: String, strategy: ConflictResolutionStrategy, actionId: UUID) -> some View {
        Button(title) {
            syncService.resolveConflict(actionId: actionId, strategy: strategy)
            expandedConflictIds.remove(actionId)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Footer

    private var footer: some View {
        let s = stats
        return HStack(spacing: AppTheme.Spacing.large) {
            Text("Space required: \(ByteCountFormatter.string(fromByteCount: Int64(s.spaceRequired), countStyle: .file))")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)

            Spacer()

            HStack(spacing: AppTheme.Spacing.medium) {
                GlassButton("Cancel", icon: "xmark", style: .secondary) {
                    syncService.state = .idle
                }

                GlassButton("Sync Selected", icon: "arrow.triangle.2.circlepath", isDisabled: !s.hasSelected) {
                    Task { await syncService.startSync() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.vertical, AppTheme.Spacing.medium)
    }

    // MARK: - Selection Helpers

    private func toggleFolderSelection(_ node: SyncTreeNode) {
        let currentState = SyncTreeBuilder.folderSelectionState(for: node, lookup: cachedActionLookup)
        let newSelected = currentState != .all

        let idsToToggle = Set(node.descendantActionIds)
        var updated = syncService.actions
        for i in updated.indices where idsToToggle.contains(updated[i].id) {
            updated[i].isSelected = newSelected
        }
        syncService.actions = updated
    }

    private func expandAllFolders() {
        func collectPaths(_ nodes: [SyncTreeNode]) {
            for node in nodes where node.isFolder {
                expandedPaths.insert(node.path)
                collectPaths(node.children)
            }
        }
        collectPaths(treeRoots)
        refreshVisibleNodes()
    }

    private func collapseRecursive(_ node: SyncTreeNode) {
        expandedPaths.remove(node.path)
        for child in node.children where child.isFolder {
            collapseRecursive(child)
        }
    }

    // MARK: - Chat Panel

    private var syncPreviewQuickActions: [String] {
        ["Sync only photos", "Deselect videos", "Select all", "Show stats"]
    }

    private var chatPanel: some View {
        AIChatPanelView(
            title: "DriveSyncAI Buddy",
            placeholder: "Try: \"sync only images\"...",
            messages: syncChatService.messages,
            input: $chatInput,
            isLoading: syncChatService.isLoading,
            quickActions: syncPreviewQuickActions,
            onSend: { sendChatMessage() },
            onClose: { showChatPanel = false },
            pendingContent: {
                if let pending = syncChatService.pendingResult, pending.hasChanges {
                    applyBanner(result: pending)
                        .id("pending-apply")
                }
            },
            extraContent: {
                if undoSnapshot != nil {
                    undoBanner
                        .id("undo-banner")
                }
            }
        )
    }

    private func applyBanner(result: SyncRefinementResult) -> some View {
        VStack(spacing: 6) {
            Text(result.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsPrimaryText)
                .multilineTextAlignment(.center)

            Button {
                applyResult(result)
            } label: {
                Text("Apply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.dsAction.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 6)
    }

    private var undoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsAction)
            Button("Undo last change") {
                restoreSnapshot()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.dsAction)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.dsAction.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
    }

    // MARK: - Chat Actions

    private func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !syncChatService.isLoading else { return }
        chatInput = ""
        Task {
            await syncChatService.send(
                userText: text,
                actions: syncService.actions,
                activeFilters: activeFileTypes,
                syncDirection: syncService.direction,
                configManager: configManager
            )
        }
    }

    // MARK: - Apply & Undo

    private func applyResult(_ result: SyncRefinementResult) {
        takeSnapshot()

        // Apply filter changes
        for change in result.filterChanges {
            if let cat = FileTypeCategory(rawValue: change.category) {
                if change.active { activeFileTypes.insert(cat) }
                else { activeFileTypes.remove(cat) }
            }
        }

        // Apply selection changes
        var updated = syncService.actions
        for change in result.selectionChanges {
            applySelectionChange(change, to: &updated)
        }
        syncService.actions = updated

        // Direction change needs confirmation
        if let dir = result.directionChange {
            pendingDirectionChange = dir
            showDirectionConfirm = true
        }

        // Expand folders
        for folder in result.expandFolders {
            expandedPaths.insert(folder)
        }
        refreshVisibleNodes()
        refreshFileTypeCounts()

        let changeCount = result.filterChanges.count + result.selectionChanges.count
        syncChatService.clearPendingResult()
        syncChatService.messages.append(
            OrganizationChatMessage(role: "system", text: "Applied \(changeCount) change\(changeCount == 1 ? "" : "s").", isStatusMessage: true)
        )
    }

    private func applySelectionChange(_ change: SyncSelectionChange, to actions: inout [SyncAction]) {
        switch change.action {
        case "selectAll":
            for i in actions.indices { actions[i].isSelected = true }
        case "deselectAll":
            for i in actions.indices { actions[i].isSelected = false }

        case "selectFolder":
            guard let target = change.target else { return }
            let selectPrefix = target.hasSuffix("/") ? target : target + "/"
            for i in actions.indices where actions[i].relativePath.hasPrefix(selectPrefix) {
                actions[i].isSelected = true
            }
        case "deselectFolder":
            guard let target = change.target else { return }
            let deselectPrefix = target.hasSuffix("/") ? target : target + "/"
            for i in actions.indices where actions[i].relativePath.hasPrefix(deselectPrefix) {
                actions[i].isSelected = false
            }

        case "selectByActionType":
            guard let target = change.target, let actionType = SyncActionType(rawValue: target) else { return }
            for i in actions.indices where actions[i].actionType == actionType {
                actions[i].isSelected = true
            }
        case "deselectByActionType":
            guard let target = change.target, let actionType = SyncActionType(rawValue: target) else { return }
            for i in actions.indices where actions[i].actionType == actionType {
                actions[i].isSelected = false
            }

        case "selectByExtension":
            guard let ext = change.target?.lowercased() else { return }
            for i in actions.indices {
                let fileExt = (actions[i].relativePath as NSString).pathExtension.lowercased()
                if fileExt == ext { actions[i].isSelected = true }
            }
        case "deselectByExtension":
            guard let ext = change.target?.lowercased() else { return }
            for i in actions.indices {
                let fileExt = (actions[i].relativePath as NSString).pathExtension.lowercased()
                if fileExt == ext { actions[i].isSelected = false }
            }

        case "selectByCategory":
            guard let target = change.target, let cat = FileTypeCategory(rawValue: target) else { return }
            for i in actions.indices {
                let ext = (actions[i].relativePath as NSString).pathExtension
                if FileTypeCategory.category(for: ext) == cat {
                    actions[i].isSelected = true
                }
            }
        case "deselectByCategory":
            guard let target = change.target, let cat = FileTypeCategory(rawValue: target) else { return }
            for i in actions.indices {
                let ext = (actions[i].relativePath as NSString).pathExtension
                if FileTypeCategory.category(for: ext) == cat {
                    actions[i].isSelected = false
                }
            }

        case "selectByMinSize":
            guard let threshold = change.threshold, let bytes = parseSize(threshold) else { return }
            for i in actions.indices where actions[i].fileSize >= bytes {
                actions[i].isSelected = true
            }
        case "deselectByMinSize":
            guard let threshold = change.threshold, let bytes = parseSize(threshold) else { return }
            for i in actions.indices where actions[i].fileSize >= bytes {
                actions[i].isSelected = false
            }

        case "selectByDateAfter":
            guard let threshold = change.threshold, let date = parseDate(threshold) else { return }
            for i in actions.indices {
                if let modDate = actions[i].sourceFile?.modificationDate ?? actions[i].targetFile?.modificationDate,
                   modDate >= date {
                    actions[i].isSelected = true
                }
            }
        case "deselectByDateBefore":
            guard let threshold = change.threshold, let date = parseDate(threshold) else { return }
            for i in actions.indices {
                if let modDate = actions[i].sourceFile?.modificationDate ?? actions[i].targetFile?.modificationDate,
                   modDate < date {
                    actions[i].isSelected = false
                }
            }

        default:
            break
        }
    }

    private func takeSnapshot() {
        undoSnapshot = UndoSnapshot(
            activeFileTypes: activeFileTypes,
            selections: Dictionary(uniqueKeysWithValues: syncService.actions.map { ($0.id, $0.isSelected) }),
            direction: syncService.direction
        )
    }

    private func restoreSnapshot() {
        guard let snapshot = undoSnapshot else { return }
        activeFileTypes = snapshot.activeFileTypes
        var updated = syncService.actions
        for i in updated.indices {
            if let sel = snapshot.selections[updated[i].id] {
                updated[i].isSelected = sel
            }
        }
        syncService.actions = updated
        syncService.direction = snapshot.direction
        undoSnapshot = nil
        syncChatService.messages.append(
            OrganizationChatMessage(role: "system", text: "Reverted to previous state.", isStatusMessage: true)
        )
    }

    private func applyDirectionChange() {
        guard let dir = pendingDirectionChange else { return }
        switch dir {
        case "oneWayMirror": syncService.direction = .oneWayMirror
        case "oneWayUpdate": syncService.direction = .oneWayUpdate
        case "bidirectional": syncService.direction = .bidirectional
        default: break
        }
        pendingDirectionChange = nil
        Task { await syncService.compare() }
    }

    // MARK: - Parse Helpers

    private func parseSize(_ str: String) -> UInt64? {
        let cleaned = str.trimmingCharacters(in: .whitespaces).uppercased()
        let multipliers: [(String, UInt64)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("KB", 1_024)
        ]
        for (suffix, mult) in multipliers {
            if cleaned.hasSuffix(suffix) {
                let numStr = cleaned.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if let num = Double(numStr) { return UInt64(num * Double(mult)) }
            }
        }
        return UInt64(cleaned)
    }

    private func parseDate(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: str)
    }
}

// MARK: - Undo Snapshot

struct UndoSnapshot {
    let activeFileTypes: Set<FileTypeCategory>
    let selections: [UUID: Bool]
    let direction: SyncDirection
}
