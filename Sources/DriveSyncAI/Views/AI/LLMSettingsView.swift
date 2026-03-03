// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct LLMSettingsView: View {
    @EnvironmentObject var configManager: LLMConfigManager
    @StateObject private var serverManager = LlamaCppServerManager.shared
    @State private var apiKeyInput = ""
    @State private var availableModels: [String] = []
    @State private var showingOllamaHelp = false
    @State private var showingModelBrowser = false
    @State private var copiedModelID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if showingModelBrowser {
                OllamaModelBrowserView(
                    selectedModelID: $configManager.activeModel,
                    copiedModelID: $copiedModelID,
                    onDismiss: { showingModelBrowser = false }
                )
            } else {
                settingsContent
            }
        }
        .onAppear {
            if configManager.activeProvider.requiresAPIKey {
                apiKeyInput = configManager.loadAPIKey(for: configManager.activeProvider) ?? ""
            }
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    providerPicker
                    providerConfig
                    connectionSection
                }
                .padding(AppTheme.Spacing.large)
            }
            footer
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Text("AI Provider Configuration")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dsPrimaryText)
            Text("Configure which LLM provider to use for AI-powered suggestions.")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(AppTheme.Spacing.large)
    }

    private var providerPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Provider")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                ForEach(LLMProviderType.allCases) { provider in
                    HStack {
                        Image(systemName: configManager.activeProvider == provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(configManager.activeProvider == provider ? Color.dsAction : Color.dsSecondaryText)
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(provider.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.dsPrimaryText)

                                if provider == .llamaCpp {
                                    Text("Default")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.purple, in: Capsule())
                                    // Live server status badge
                                    if configManager.activeProvider == .llamaCpp {
                                        HStack(spacing: 3) {
                                            Circle()
                                                .fill(serverManager.isRunning ? Color.green : Color.orange)
                                                .frame(width: 5, height: 5)
                                            Text(serverManager.isRunning ? "Running" : "Stopped")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(serverManager.isRunning ? .green : .orange)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            (serverManager.isRunning ? Color.green : Color.orange).opacity(0.1),
                                            in: Capsule()
                                        )
                                    }
                                }
                                if provider == .perplexity {
                                    Text("Basic")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange, in: Capsule())
                                }
                            }
                            Text(provider.privacyNote)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.dsTertiaryText)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let previous = configManager.activeProvider
                        // Stop built-in server if switching away
                        if previous == .llamaCpp && provider != .llamaCpp {
                            LlamaCppServerManager.shared.stop()
                        }
                        configManager.activeProvider = provider
                        configManager.activeModel = provider.defaultModel
                        configManager.connectionStatus = .unknown
                        if provider.requiresAPIKey {
                            apiKeyInput = configManager.loadAPIKey(for: provider) ?? ""
                        }
                        // Auto-start built-in server if switching to it
                        if provider == .llamaCpp {
                            Task { await LlamaCppServerManager.shared.start() }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var providerConfig: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Configuration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                if configManager.activeProvider == .llamaCpp {
                    llamaCppConfig
                } else if configManager.activeProvider == .ollama {
                    ollamaConfig
                } else {
                    cloudProviderConfig
                }

                if configManager.activeProvider == .llamaCpp || configManager.activeProvider == .ollama {
                    if configManager.activeProvider == .ollama { ollamaModelSelector }
                } else {
                    HStack {
                        Text("Model")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsSecondaryText)
                        Spacer()
                        Picker("", selection: $configManager.activeModel) {
                            ForEach(availableModels.isEmpty ? configManager.activeProvider.knownModels : availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    private var ollamaModelSelector: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Model")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
                Spacer()

                if let catalogModel = OllamaModelCatalog.model(withID: configManager.activeModel) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(catalogModel.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.dsPrimaryText)
                        Text(catalogModel.category.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                } else {
                    Text(configManager.activeModel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                }
            }

            HStack(spacing: AppTheme.Spacing.small) {
                Button(action: { showingModelBrowser = true }) {
                    Label("Browse Models", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                pullCommandButton(for: configManager.activeModel)
            }

            if let catalogModel = OllamaModelCatalog.model(withID: configManager.activeModel) {
                Text(catalogModel.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
                    .padding(.top, 2)
            }
        }
    }

    private func pullCommandButton(for modelID: String) -> some View {
        let command = "ollama pull \(modelID)"
        let isCopied = copiedModelID == modelID

        return Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copiedModelID = modelID
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedModelID == modelID { copiedModelID = nil }
            }
        }) {
            Label(
                isCopied ? "Copied!" : "Copy Pull Command",
                systemImage: isCopied ? "checkmark" : "doc.on.clipboard"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isCopied ? .green : Color.dsAction)
        }
        .buttonStyle(.bordered)
    }

    private var llamaCppConfig: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: serverManager.isRunning ? "cpu.fill" : "cpu")
                        .font(.system(size: 16))
                        .foregroundStyle(serverManager.isRunning ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(serverManager.isRunning ? "Engine running on localhost:\(LlamaCppServerManager.port)" : "Engine not running")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(serverManager.isRunning ? Color.dsPrimaryText : Color.dsSecondaryText)
                    Text(serverManager.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
                Spacer()
                if !serverManager.isRunning && LlamaCppServerManager.shared.isReady {
                    Button("Start") {
                        Task { await LlamaCppServerManager.shared.start() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsSecondaryText)
                Text("Model: qwen2.5-1.5b-instruct-q4_k_m.gguf · Apache 2.0 · ~986 MB")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
    }

    private var ollamaConfig: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Base URL")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
                Spacer()
                TextField("http://localhost:11434", text: Binding(
                    get: { configManager.customBaseURL ?? "http://localhost:11434" },
                    set: { configManager.customBaseURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }

            Button(action: { showingOllamaHelp.toggle() }) {
                Label("Ollama Setup Help", systemImage: "questionmark.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.link)
            .popover(isPresented: $showingOllamaHelp) {
                ollamaHelpPopover
            }
        }
    }

    private var ollamaHelpPopover: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Install Ollama")
                .font(.system(size: 14, weight: .bold))
            Text("1. Download from https://ollama.com")
            Text("2. Install and launch Ollama")
            Text("3. Pull the recommended model:")

            HStack {
                Text("ollama pull llama3.2")
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsSecondaryBackground, in: RoundedRectangle(cornerRadius: 4))

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("ollama pull llama3.2", forType: .string)
                    copiedModelID = "__help__"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedModelID == "__help__" { copiedModelID = nil }
                    }
                }) {
                    Image(systemName: copiedModelID == "__help__" ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(copiedModelID == "__help__" ? .green : Color.dsAction)
                }
                .buttonStyle(.plain)
            }

            Text("4. Click 'Test Connection' below")

            Link("Download Ollama", destination: URL(string: "https://ollama.com")!)
                .font(.system(size: 12, weight: .medium))
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.dsSecondaryText)
        .padding(AppTheme.Spacing.large)
        .frame(width: 320)
    }

    private var cloudProviderConfig: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("API Key")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
                Spacer()
                SecureField("Paste your API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onChange(of: apiKeyInput) { _, newValue in
                        if !newValue.isEmpty {
                            configManager.saveAPIKey(newValue, for: configManager.activeProvider)
                        }
                    }
            }

            if configManager.activeProvider == .perplexity {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text("Perplexity has limited structured output support. For best results, use OpenAI, Anthropic, or Ollama.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }
        }
    }

    private var connectionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                HStack {
                    Text("Connection Status")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(configManager.connectionStatus.displayText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }

                Button("Test Connection") {
                    Task {
                        await configManager.validateConnection()
                        if configManager.connectionStatus == .connected {
                            availableModels = await configManager.fetchAvailableModels()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                configManager.saveConfig()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppTheme.Spacing.large)
    }

    private var statusColor: Color {
        switch configManager.connectionStatus {
        case .connected: return .green
        case .checking: return .yellow
        case .disconnected: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Ollama Model Browser

struct OllamaModelBrowserView: View {
    @Binding var selectedModelID: String
    @Binding var copiedModelID: String?
    var onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedCategory: OllamaModelCategory?

    private var filteredModels: [OllamaModel] {
        var models = selectedCategory == nil ? OllamaModelCatalog.all : OllamaModelCatalog.models(for: selectedCategory!)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            models = models.filter {
                $0.displayName.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
            }
        }
        return models
    }

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            categoryFilter
            Divider()
            modelList
            browserFooter
        }
        .frame(width: 640, height: 620)
    }

    private var browserHeader: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsAction)

                Spacer()
            }

            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Ollama Model Library")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.dsPrimaryText)
            }

            Text("\(OllamaModelCatalog.all.count) open-source models across \(OllamaModelCategory.allCases.count) categories")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsTertiaryText)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.dsSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.top, AppTheme.Spacing.large)
        .padding(.bottom, AppTheme.Spacing.small)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryPill(nil, label: "All", icon: "square.grid.2x2")
                ForEach(OllamaModelCategory.allCases) { cat in
                    categoryPill(cat, label: cat.rawValue, icon: cat.icon)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, 8)
        }
    }

    private func categoryPill(_ category: OllamaModelCategory?, label: String, icon: String) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: { selectedCategory = category }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : Color.dsPrimaryText)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.dsSecondaryBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredModels) { model in
                    modelRow(model)
                    if model.id != filteredModels.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }

                if filteredModels.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.dsTertiaryText)
                        Text("No models match your search")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .padding(40)
                }
            }
        }
    }

    private func modelRow(_ model: OllamaModel) -> some View {
        let isSelected = selectedModelID == model.id
        let isCopied = copiedModelID == model.id

        return HStack(spacing: 12) {
            Image(systemName: model.category.icon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.dsAction : Color.dsSecondaryText)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)

                    if model.recommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green, in: Capsule())
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsAction)
                    }
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    ForEach(model.sizes, id: \.self) { size in
                        Text(size)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.dsSecondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.dsSecondaryBackground, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.pullCommand, forType: .string)
                    copiedModelID = model.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedModelID == model.id { copiedModelID = nil }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text(isCopied ? "Copied!" : "Pull")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? .green : Color.dsAction)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isCopied ? Color.green.opacity(0.1) : Color.dsAction.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
                .buttonStyle(.plain)
                .help("Copy: \(model.pullCommand)")

                if !isSelected {
                    Button("Select") {
                        selectedModelID = model.id
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, 10)
        .background(isSelected ? Color.dsAction.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedModelID = model.id
        }
    }

    private var browserFooter: some View {
        HStack {
            Link(destination: URL(string: "https://ollama.com/library")!) {
                Label("View all on ollama.com", systemImage: "arrow.up.right.square")
                    .font(.system(size: 12))
            }

            Spacer()

            if let model = OllamaModelCatalog.model(withID: selectedModelID) {
                Text("Selected: \(model.displayName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(AppTheme.Spacing.large)
        .background(.ultraThinMaterial)
    }
}
