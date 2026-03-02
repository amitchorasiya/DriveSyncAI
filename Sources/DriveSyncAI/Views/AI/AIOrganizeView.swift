// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct AIOrganizeView: View {
    @EnvironmentObject var reorganizeService: ReorganizeService
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @EnvironmentObject var configManager: LLMConfigManager
    @EnvironmentObject var customRulesService: CustomRulesService
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("hasAcceptedAIDisclaimer") private var hasAcceptedAIDisclaimer = false
    @State private var selectedDriveURL: URL?
    @State private var showingLLMSettings = false
    @State private var showingAIDisclaimer = false
    @StateObject private var preferencesStore = OrganizationPreferencesStore()
    @StateObject private var chatService = OrganizationChatService()
    @State private var refinementInput = ""
    @State private var showRefinementPanel = false
    @State private var postScanChatInput = ""
    @State private var showPostScanChat = true
    @State private var highlightedMoveIds: Set<UUID> = []
    @State private var showBuddyPanel = true
    @State private var buddyInput = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                headerBar

                if !aiEnabled {
                    aiDisabledState
                } else if !hasAcceptedAIDisclaimer {
                    disclaimerRequired
                } else {
                    mainContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if aiEnabled && hasAcceptedAIDisclaimer && showBuddyPanel {
                AIChatPanelView(
                    title: "DriveSyncAI Buddy",
                    placeholder: buddyPlaceholder,
                    messages: chatService.messages,
                    input: $buddyInput,
                    isLoading: chatService.isLoading,
                    quickActions: organizeBuddyQuickActions,
                    onSend: { sendBuddyMessage() },
                    onClose: { showBuddyPanel = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showBuddyPanel)
        .sheet(isPresented: $showingLLMSettings) {
            LLMSettingsView()
                .environmentObject(configManager)
        }
        .sheet(isPresented: $showingAIDisclaimer) {
            AIDisclaimerView()
        }
    }

    private var organizeBuddyQuickActions: [String] {
        switch reorganizeService.phase {
        case .idle:
            return ["Group photos by month", "What folder structures work best?", "How does AI classify files?"]
        case .planReady:
            return ["Show plan", "Move PDFs to Documents", "Exclude node_modules", "Show cleanup options"]
        default:
            return []
        }
    }

    private var buddyPlaceholder: String {
        switch reorganizeService.phase {
        case .idle:
            return "e.g. \"Group photos by month\""
        case .planReady:
            return "e.g. \"Move invoices to Finance/2024\""
        default:
            return "Ask about your organization..."
        }
    }

    private func sendBuddyMessage() {
        let text = buddyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        buddyInput = ""

        switch reorganizeService.phase {
        case .idle:
            Task {
                let result = await chatService.send(
                    userText: text,
                    preferences: preferencesStore.preferences,
                    configManager: configManager
                )
                if let prefChanges = result.preferenceChanges, !prefChanges.isEmpty {
                    OrganizationChatService.applyPreferenceChanges(prefChanges, to: &preferencesStore.preferences)
                    chatService.messages.append(
                        OrganizationChatMessage(role: "system", text: "Updated preferences based on your request.", isStatusMessage: true)
                    )
                }
            }
        case .planReady:
            Task {
                let result = await chatService.send(
                    userText: text,
                    preferences: preferencesStore.preferences,
                    analysis: reorganizeService.currentAnalysis,
                    plan: reorganizeService.currentPlan,
                    configManager: configManager
                )
                if let prefChanges = result.preferenceChanges, !prefChanges.isEmpty {
                    OrganizationChatService.applyPreferenceChanges(prefChanges, to: &preferencesStore.preferences)
                }
                if let mods = result.planModifications, !mods.isEmpty, var plan = reorganizeService.currentPlan {
                    let descriptions = OrganizationChatService.applyPlanModifications(mods, to: &plan)
                    reorganizeService.currentPlan = plan
                    let changedIds = Set(mods.compactMap { mod -> UUID? in
                        guard let fileName = mod.fileName else { return nil }
                        return plan.moveActions.first { $0.fileName.localizedCaseInsensitiveContains(fileName) }?.id
                    })
                    withAnimation { highlightedMoveIds = changedIds }
                    chatService.lastAppliedChangesCount = descriptions.count
                    if !descriptions.isEmpty {
                        let summary = descriptions.joined(separator: "\n")
                        chatService.messages.append(
                            OrganizationChatMessage(role: "system", text: "Applied \(descriptions.count) change(s):\n\(summary)", isStatusMessage: true)
                        )
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run { withAnimation { highlightedMoveIds = [] } }
                    }
                }
                if result.shouldReAnalyze {
                    chatService.messages.append(
                        OrganizationChatMessage(role: "system", text: "Re-analyzing with updated preferences...", isStatusMessage: true)
                    )
                    preferencesStore.save()
                    if let url = selectedDriveURL {
                        await reorganizeService.analyze(root: url, preferences: preferencesStore.preferences)
                    }
                }
            }
        default:
            chatService.messages.append(
                OrganizationChatMessage(role: "assistant", text: "I can help once the scan is complete or when you're setting up preferences. Hang tight!")
            )
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Organize")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Analyze, categorize, and reorganize your drive with AI assistance")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Spacer()

            if aiEnabled && hasAcceptedAIDisclaimer {
                Button(action: { showingLLMSettings = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(configManager.activeProvider.displayName)
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                AIChatToggleButton(isVisible: $showBuddyPanel)
            }
        }
        .padding(AppTheme.Spacing.large)
    }

    // MARK: - Disabled State

    private var aiDisabledState: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            Text("AI Features are Disabled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            Text("Enable AI features in Settings to use AI-powered organization.")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    private var disclaimerRequired: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text("AI Disclaimer Required")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            Text("You need to review and accept the AI features disclaimer before using this feature.")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
                .multilineTextAlignment(.center)

            GlassButton("Review Disclaimer", icon: "doc.text", style: .primary) {
                showingAIDisclaimer = true
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            switch reorganizeService.phase {
            case .idle:
                selectAndAnalyzePhase
            case .scanning, .enriching:
                scanningPhase
            case .aiProcessing:
                aiProcessingPhase
            case .planReady:
                planReadyPhase
            case .executing:
                executingPhase
            case .completed:
                completedPhase
            case .failed:
                failedPhase
            }
        }
    }

    // MARK: - Phase 1: Select & Analyze

    private var selectAndAnalyzePhase: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                GlassCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        sectionHeader(icon: "externaldrive.fill", title: "Select Drive or Folder", color: .blue)

                        if volumeMonitor.mountedVolumes.isEmpty {
                            Text("No external drives detected. You can still select a folder.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.dsSecondaryText)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.Spacing.medium) {
                                    ForEach(volumeMonitor.mountedVolumes) { drive in
                                        driveCard(drive.url)
                                            .overlay(alignment: .topTrailing) {
                                                Text(drive.name)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(Color.dsTertiaryText)
                                            }
                                    }
                                }
                            }
                        }

                        HStack {
                            Button("Choose Folder...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK {
                                    selectedDriveURL = panel.url
                                }
                            }
                            .buttonStyle(.bordered)

                            if let url = selectedDriveURL {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.dsPrimaryText)
                                }
                            }
                        }
                    }
                }

                organizationPreferencesSection

                GlassButton("Analyze Drive", icon: "magnifyingglass", style: .primary, isDisabled: selectedDriveURL == nil) {
                    if let url = selectedDriveURL {
                        preferencesStore.save()
                        Task { await reorganizeService.analyze(root: url, preferences: preferencesStore.preferences) }
                    }
                }

                howItWorksSection
            }
            .padding(AppTheme.Spacing.large)
        }
    }

    private func driveCard(_ vol: URL) -> some View {
        GlassCard {
            VStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedDriveURL == vol ? Color.dsAction : Color.dsSecondaryText)
                Text(vol.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 80, height: 60)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(selectedDriveURL == vol ? Color.dsAction : .clear, lineWidth: 2)
        )
        .onTapGesture { selectedDriveURL = vol }
    }

    private var organizationPreferencesSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Structure & naming
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    sectionHeader(icon: "folder.fill.badge.gearshape", title: "Structure & Naming", color: .purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Folder structure")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.dsSecondaryText)
                        Picker("Folder Structure", selection: $preferencesStore.preferences.folderStructure) {
                            ForEach(FolderStructurePreference.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Text(preferencesStore.preferences.folderStructure.detailDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiaryText)
                        .padding(.leading, 2)

                    if preferencesStore.preferences.folderStructure == .customRoot {
                        TextField("Custom root folder name", text: $preferencesStore.preferences.customRootFolderName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("File naming")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.dsSecondaryText)
                        Picker("Naming", selection: $preferencesStore.preferences.namingConvention) {
                            ForEach(NamingConventionPreference.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if preferencesStore.preferences.namingConvention == .customPrefix {
                        TextField("Name prefix (e.g. project_)", text: $preferencesStore.preferences.customNamePrefix)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }
            }

            // Scope & duplicates
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    sectionHeader(icon: "scope", title: "Scope & Duplicates", color: .teal)

                    HStack(spacing: AppTheme.Spacing.large) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan depth")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.dsSecondaryText)
                            Picker("Scope", selection: $preferencesStore.preferences.scope) {
                                ForEach(OrganizationScopePreference.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("When duplicates found")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.dsSecondaryText)
                            Picker("Duplicates", selection: $preferencesStore.preferences.duplicatesHandling) {
                                ForEach(DuplicatesHandlingPreference.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
            }

            // Priority types
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        sectionHeader(icon: "star.fill", title: "Priority File Types", color: .orange)
                        Spacer()
                        if preferencesStore.preferences.priorityCategories.isEmpty {
                            Text("All types included")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsTertiaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.dsSecondaryFill, in: Capsule())
                        } else {
                            Text("\(preferencesStore.preferences.priorityCategories.count) selected")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.dsAction)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.dsAction.opacity(0.1), in: Capsule())
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(FileCategory.allCases) { category in
                            let isSelected = preferencesStore.preferences.priorityCategories.contains(category)
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isSelected {
                                        preferencesStore.preferences.priorityCategories.remove(category)
                                    } else {
                                        preferencesStore.preferences.priorityCategories.insert(category)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? Color.dsAction : Color.dsSecondaryText)
                                    Text(category.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Color.dsPrimaryText : Color.dsSecondaryText)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    isSelected ? Color.dsAction.opacity(0.15) : Color.dsSecondaryFill,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.dsAction.opacity(0.3) : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Cleanup
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    sectionHeader(icon: "paintbrush.fill", title: "Cleanup Preferences", color: .green)

                    VStack(spacing: AppTheme.Spacing.small) {
                        cleanupToggle(
                            title: "Temporary files",
                            subtitle: ".tmp, .cache, partial downloads",
                            icon: "doc.badge.clock",
                            isOn: $preferencesStore.preferences.cleanup.includeTempFiles
                        )
                        cleanupToggle(
                            title: "System junk",
                            subtitle: ".DS_Store, Thumbs.db, desktop.ini",
                            icon: "gearshape.2",
                            isOn: $preferencesStore.preferences.cleanup.includeSystemJunk
                        )
                        cleanupToggle(
                            title: "Empty folders",
                            subtitle: "Directories with no files inside",
                            icon: "folder.badge.minus",
                            isOn: $preferencesStore.preferences.cleanup.includeEmptyFolders
                        )

                        Divider()

                        cleanupToggle(
                            title: "Safe delete (non-destructive)",
                            subtitle: "Move to _Deleted/ preserving folder structure instead of permanent delete",
                            icon: "trash.slash",
                            isOn: $preferencesStore.preferences.cleanup.useSoftDelete
                        )
                    }
                }
            }

            // Advanced options
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    sectionHeader(icon: "gearshape.2.fill", title: "Advanced Options", color: .indigo)

                    cleanupToggle(
                        title: "Split installers by platform",
                        subtitle: "Create SW/Windows and SW/Mac sub-folders for installers",
                        icon: "arrow.down.app",
                        isOn: $preferencesStore.preferences.splitInstallersByPlatform
                    )

                    cleanupToggle(
                        title: "Track emptied source folders",
                        subtitle: "Move emptied folders to _Sorted_Originals/ for review",
                        icon: "folder.badge.questionmark",
                        isOn: $preferencesStore.preferences.moveEmptiedSourcesToHolding
                    )

                    cleanupToggle(
                        title: "Generate manifests",
                        subtitle: "Create before/after file listings for data integrity verification",
                        icon: "doc.text.magnifyingglass",
                        isOn: $preferencesStore.preferences.generateManifests
                    )

                    cleanupToggle(
                        title: "Use exiftool (if installed)",
                        subtitle: "Better EXIF extraction for photos — requires 'brew install exiftool'",
                        icon: "camera.metering.matrix",
                        isOn: $preferencesStore.preferences.useExiftool
                    )
                }
            }

            // AI refinement
            refinementPanel
        }
    }

    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
        }
    }

    private func cleanupToggle(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsPrimaryText)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dsTertiaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var refinementPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showRefinementPanel.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            Image(systemName: "brain")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Refine with AI")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.dsPrimaryText)
                            Text("Describe how you want files organized in plain English")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                        Spacer()
                        Image(systemName: showRefinementPanel ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .buttonStyle(.plain)

                if showRefinementPanel {
                    Divider()

                    if chatService.messages.isEmpty && !chatService.isLoading {
                        HStack(spacing: AppTheme.Spacing.small) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.dsTertiaryText)
                            Text("Try: \"Put all tax PDFs in Taxes/2024\" or \"Group photos by month\"")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppTheme.Spacing.medium)
                    }

                    if !chatService.messages.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(chatService.messages) { message in
                                        chatBubble(message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 180)
                            .background(Color.dsSecondaryFill.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            .onChange(of: chatService.messages.count) {
                                if let last = chatService.messages.last {
                                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Describe your organization preferences…", text: $refinementInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit {
                                sendRefinement()
                            }

                        if chatService.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                sendRefinement()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        refinementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.dsSecondaryText.opacity(0.4)
                                            : Color.dsAction,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(refinementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let err = chatService.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(err)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                    }

                    if !chatService.ruleCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.purple)
                                Text("Suggested Rules")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.dsPrimaryText)
                                Spacer()
                                Text("Select to save")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.dsTertiaryText)
                            }

                            VStack(spacing: 4) {
                                ForEach($chatService.ruleCandidates) { $candidate in
                                    HStack(spacing: 8) {
                                        Toggle("", isOn: $candidate.selectedForSave)
                                            .toggleStyle(.checkbox)
                                            .labelsHidden()
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(Color.dsPrimaryText)
                                            HStack(spacing: 4) {
                                                Text(candidate.pattern)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(Color.dsSecondaryText)
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(Color.dsTertiaryText)
                                                Text(candidate.destination)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.purple)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(
                                        candidate.selectedForSave ? Color.purple.opacity(0.06) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                            }

                            let hasSelected = chatService.ruleCandidates.contains(where: \.selectedForSave)
                            GlassButton(
                                "Save Selected as Custom Rules",
                                icon: "square.and.arrow.down",
                                style: .secondary,
                                isDisabled: !hasSelected
                            ) {
                                saveSelectedRuleCandidates()
                            }
                        }
                        .padding(AppTheme.Spacing.small)
                        .background(Color.dsSecondaryFill.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func chatBubble(_ message: OrganizationChatMessage) -> some View {
        let isUser = message.role == "user"
        let isSystem = message.role == "system"

        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                if isSystem {
                    HStack(spacing: 4) {
                        Image(systemName: message.text.contains("Re-analyzing") ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(message.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(isUser ? .white : Color.dsPrimaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isUser
                                ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.dsSecondaryFill),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
            }
            if !isUser && !isSystem { Spacer(minLength: 40) }
            if isSystem { Spacer(minLength: 20) }
        }
        .padding(.horizontal, 6)
    }

    private func sendRefinement() {
        let text = refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        refinementInput = ""
        Task {
            let result = await chatService.send(
                userText: text,
                preferences: preferencesStore.preferences,
                configManager: configManager
            )

            if let prefChanges = result.preferenceChanges, !prefChanges.isEmpty {
                OrganizationChatService.applyPreferenceChanges(prefChanges, to: &preferencesStore.preferences)
                chatService.messages.append(
                    OrganizationChatMessage(role: "system", text: "Updated preferences based on your request.", isStatusMessage: true)
                )
            }
        }
    }

    private func saveSelectedRuleCandidates() {
        let selected = chatService.ruleCandidates.filter(\.selectedForSave)
        guard !selected.isEmpty else { return }
        for candidate in selected {
            let rule = CustomRule(
                name: candidate.name,
                pattern: candidate.pattern,
                destination: candidate.destination
            )
            customRulesService.addRule(rule)
        }
    }

    private var howItWorksSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("How It Works")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                HStack(spacing: AppTheme.Spacing.large) {
                    tierInfo(number: "1", title: "Rules", desc: "Extension-based categorization + your custom rules", color: .green)
                    tierInfo(number: "2", title: "Metadata", desc: "EXIF dates, PDF titles, Spotlight attributes", color: .blue)
                    tierInfo(number: "3", title: "AI", desc: "Only ambiguous files get sent to the LLM", color: .purple)
                }
            }
        }
    }

    private func tierInfo(number: String, title: String, desc: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(number)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(color, in: Circle())
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
            }
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(Color.dsTertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Phase 2: Scanning

    private var scanningPhase: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            ProgressView(value: reorganizeService.analysisProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 400)

            Text(reorganizeService.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)

            Text(reorganizeService.phase.rawValue)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTertiaryText)

            GlassButton("Cancel", icon: "xmark", style: .secondary) {
                chatService.clear()
                reorganizeService.reset()
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    private var aiProcessingPhase: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            ProgressView()
                .controlSize(.large)

            Text(reorganizeService.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)

            Text("Using \(configManager.activeProvider.displayName) / \(configManager.activeModel)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.dsTertiaryText)

            GlassButton("Cancel", icon: "xmark", style: .secondary) {
                chatService.clear()
                reorganizeService.reset()
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Phase 3: Plan Ready

    private var planReadyPhase: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                GlassButton("Back to Setup", icon: "arrow.uturn.backward", style: .secondary) {
                    chatService.clear()
                    reorganizeService.reset()
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.medium)

            if let analysis = reorganizeService.currentAnalysis {
                analysisSummary(analysis)
            }

            if !(reorganizeService.currentAnalysis?.ambiguousFiles.isEmpty ?? true) && reorganizeService.currentPlan?.aiModelUsed == nil {
                aiSuggestionPrompt
            }

            if let errorMsg = reorganizeService.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
            }

            postScanChatPanel
                .padding(.horizontal, AppTheme.Spacing.medium)

            if let plan = reorganizeService.currentPlan {
                ReorganizePlanView(plan: Binding(
                    get: { reorganizeService.currentPlan ?? plan },
                    set: { reorganizeService.currentPlan = $0 }
                ), highlightedIds: highlightedMoveIds) { dryRun in
                    Task { await reorganizeService.executePlan(dryRun: dryRun) }
                }
            }
        }
        .onAppear {
            chatService.addWelcomeMessage(
                analysis: reorganizeService.currentAnalysis,
                plan: reorganizeService.currentPlan
            )
        }
    }

    // MARK: - Post-Scan Chat Panel

    private var postScanChatPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPostScanChat.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 26, height: 26)
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Refine Plan with AI")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.dsPrimaryText)
                            Text("Tell me what to change — I'll update the plan for you")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                        Spacer()
                        if chatService.lastAppliedChangesCount > 0 {
                            Text("\(chatService.lastAppliedChangesCount) changes applied")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.1), in: Capsule())
                        }
                        Image(systemName: showPostScanChat ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .buttonStyle(.plain)

                if showPostScanChat {
                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(chatService.messages) { message in
                                    chatBubble(message)
                                        .id(message.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 220)
                        .background(Color.dsSecondaryFill.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: chatService.messages.count) {
                            if let last = chatService.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("e.g. \"Move all invoices to Finance/2024\"", text: $postScanChatInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { sendPostScanMessage() }

                        if chatService.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                sendPostScanMessage()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        postScanChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.dsSecondaryText.opacity(0.4)
                                            : Color.dsAction,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(postScanChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let err = chatService.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(err)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                    }

                    if !chatService.ruleCandidates.isEmpty {
                        postScanRuleCandidates
                    }
                }
            }
        }
    }

    private var postScanRuleCandidates: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text("Suggested Rules")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Spacer()
                Text("Select to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dsTertiaryText)
            }

            VStack(spacing: 4) {
                ForEach($chatService.ruleCandidates) { $candidate in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $candidate.selectedForSave)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.dsPrimaryText)
                            HStack(spacing: 4) {
                                Text(candidate.pattern)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.dsSecondaryText)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.dsTertiaryText)
                                Text(candidate.destination)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.purple)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        candidate.selectedForSave ? Color.purple.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }

            let hasSelected = chatService.ruleCandidates.contains(where: \.selectedForSave)
            GlassButton(
                "Save Selected as Custom Rules",
                icon: "square.and.arrow.down",
                style: .secondary,
                isDisabled: !hasSelected
            ) {
                saveSelectedRuleCandidates()
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.dsSecondaryFill.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sendPostScanMessage() {
        let text = postScanChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isLoading else { return }
        postScanChatInput = ""
        Task {
            let result = await chatService.send(
                userText: text,
                preferences: preferencesStore.preferences,
                analysis: reorganizeService.currentAnalysis,
                plan: reorganizeService.currentPlan,
                configManager: configManager
            )

            // Apply preference changes
            if let prefChanges = result.preferenceChanges, !prefChanges.isEmpty {
                OrganizationChatService.applyPreferenceChanges(prefChanges, to: &preferencesStore.preferences)
            }

            // Apply plan modifications
            if let mods = result.planModifications, !mods.isEmpty, var plan = reorganizeService.currentPlan {
                let descriptions = OrganizationChatService.applyPlanModifications(mods, to: &plan)
                reorganizeService.currentPlan = plan

                // Highlight changed items
                let changedIds = Set(mods.compactMap { mod -> UUID? in
                    guard let fileName = mod.fileName else { return nil }
                    return plan.moveActions.first { $0.fileName.localizedCaseInsensitiveContains(fileName) }?.id
                })
                withAnimation { highlightedMoveIds = changedIds }
                chatService.lastAppliedChangesCount = descriptions.count

                if !descriptions.isEmpty {
                    let summary = descriptions.joined(separator: "\n")
                    chatService.messages.append(
                        OrganizationChatMessage(role: "system", text: "Applied \(descriptions.count) change(s):\n\(summary)", isStatusMessage: true)
                    )
                }

                // Clear highlights after delay
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        withAnimation { highlightedMoveIds = [] }
                    }
                }
            }

            // Re-analyze if needed
            if result.shouldReAnalyze {
                chatService.messages.append(
                    OrganizationChatMessage(role: "system", text: "Re-analyzing with updated preferences...", isStatusMessage: true)
                )
                preferencesStore.save()
                if let url = selectedDriveURL {
                    await reorganizeService.analyze(root: url, preferences: preferencesStore.preferences)
                }
            }
        }
    }

    private func analysisSummary(_ analysis: DriveAnalysis) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.medium) {
                ForEach(analysis.categories.sorted(by: { $0.value.fileCount > $1.value.fileCount }), id: \.key) { cat, stats in
                    GlassCard {
                        VStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.dsAction)
                            Text("\(stats.fileCount)")
                                .font(.system(size: 14, weight: .bold))
                            Text(cat.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsSecondaryText)
                            Text(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                        .frame(width: 70)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
        }
    }

    private var aiSuggestionPrompt: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(reorganizeService.currentAnalysis?.ambiguousFiles.count ?? 0) files need AI classification")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                    Text("Get AI suggestions from \(configManager.activeProvider.displayName) for better organization.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaryText)
                }

                Spacer()

                GlassButton("Get AI Suggestions", icon: "brain", style: .primary) {
                    Task { await reorganizeService.getAISuggestions() }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
    }

    // MARK: - Executing & Completed

    private var executingPhase: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            ProgressView(value: reorganizeService.executionProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 400)

            Text(reorganizeService.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    private var completedPhase: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("Reorganization Complete")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            Text(reorganizeService.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)

            if let plan = reorganizeService.currentPlan {
                postExecutionSummary(plan)
            }

            GlassButton("Start New Analysis", icon: "arrow.counterclockwise", style: .secondary) {
                chatService.clear()
                reorganizeService.reset()
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }

    private func postExecutionSummary(_ plan: ReorganizePlan) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                sectionHeader(icon: "list.bullet.clipboard", title: "Execution Summary", color: .green)

                HStack(spacing: AppTheme.Spacing.large) {
                    summaryPill(icon: "arrow.right.doc.on.clipboard", label: "Moved", count: plan.totalAcceptedMoves)
                    summaryPill(icon: "pencil", label: "Renamed", count: plan.totalAcceptedRenames)
                    summaryPill(icon: "paintbrush", label: "Cleaned", count: plan.totalAcceptedClutter)
                }

                let softDeleted = plan.clutterActions.filter { $0.accepted && $0.action == .softDelete }.count
                if softDeleted > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("\(softDeleted) items moved to _Deleted/ (safe to review & permanently remove later)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }

                if !plan.emptiedSourceFolders.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                        Text("\(plan.emptiedSourceFolders.count) emptied folders moved to _Sorted_Originals/")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: 500)
    }

    private func summaryPill(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.dsAction)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    private var failedPhase: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Something went wrong")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            if let error = reorganizeService.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)
                    .multilineTextAlignment(.center)
            }

            GlassButton("Try Again", icon: "arrow.counterclockwise", style: .secondary) {
                chatService.clear()
                reorganizeService.reset()
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }
}
