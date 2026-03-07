// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import UniformTypeIdentifiers

enum AskMyDocsTab: String, CaseIterable {
    case ask = "Ask"
    case taxReview = "Tax Review"

    var icon: String {
        switch self {
        case .ask: return "bubble.left.and.text.bubble.right"
        case .taxReview: return "doc.text.magnifyingglass"
        }
    }
}

struct AskMyDocsView: View {
    @EnvironmentObject var configManager: LLMConfigManager
    @StateObject private var insightService = DocumentInsightService()
    @StateObject private var chatService = AskMyDocsChatService()

    @State private var selectedTab: AskMyDocsTab = .ask
    @State private var showChatPanel = true
    @State private var chatInput = ""
    @State private var showExportOptions = false
    @AppStorage("hasAcceptedAIDisclaimer") private var hasAcceptedAIDisclaimer = false

    var body: some View {
        HStack(spacing: 0) {
            mainContent
            if showChatPanel {
                chatPanel
            }
        }
        .onAppear {
            chatService.addWelcomeMessage()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    tabPicker
                    
                    switch selectedTab {
                    case .ask:
                        askModeContent
                    case .taxReview:
                        TaxReviewView(
                            insightService: insightService,
                            chatService: chatService,
                            configManager: configManager
                        )
                    }
                }
                .padding(AppTheme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask My Docs")
                    .font(.title2.bold())
                    .foregroundStyle(Color.dsPrimaryText)

                if !insightService.corpus.successfulDocuments.isEmpty {
                    Text("\(insightService.corpus.supportedFileCount) documents | \(insightService.corpus.detectedDomain.displayName) | \(insightService.corpus.totalChars) chars")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }

            Spacer()

            if insightService.piiProtectionEnabled {
                piiShieldBadge
            }

            if let rec = chatService.modelRecommendation {
                modelRecommendationBadge(rec)
            }

            Button {
                showChatPanel.toggle()
            } label: {
                Image(systemName: showChatPanel ? "sidebar.right" : "bubble.left.and.text.bubble.right")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Toggle chat panel")
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.medium)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(AskMyDocsTab.allCases, id: \.rawValue) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.dsSecondaryText)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Ask Mode Content

    private var askModeContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            piiProtectionSection
            sourceManagementSection
            
            if insightService.isScanning {
                scanProgressSection
            }

            if !insightService.corpus.successfulDocuments.isEmpty {
                if !insightService.redactionSummary.isEmpty {
                    redactionSummaryBanner
                }
                if let rec = chatService.modelRecommendation {
                    modelRecommendationBanner(rec)
                }
                documentInventorySection
                if let result = chatService.lastInsightResult, !result.dataPoints.isEmpty {
                    dataPointsSection(result)
                }
            }
        }
    }

    // MARK: - PII Protection

    private var piiShieldBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.checkered")
                .font(.caption)
                .foregroundStyle(.green)
            Text("PII Protected")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(4)
        .help("Sensitive data (SSNs, account numbers) is redacted before being sent to the AI model")
    }

    private var piiProtectionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: insightService.piiProtectionEnabled ? "shield.checkered" : "shield.slash")
                .font(.title3)
                .foregroundStyle(insightService.piiProtectionEnabled ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text("PII Protection")
                    .font(.subheadline.bold())
                Text(insightService.piiProtectionEnabled
                     ? "SSNs, account numbers, and other sensitive data are automatically redacted before reaching the AI model."
                     : "PII protection is OFF. Sensitive data may be sent to the AI provider.")
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Spacer()

            if insightService.piiProtectionEnabled {
                Picker("", selection: $insightService.piiSensitivityLevel) {
                    ForEach(PIISensitivityLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: insightService.piiSensitivityLevel) { _ in
                    Task { await insightService.applyPIIRedaction() }
                }
            }

            Toggle("", isOn: $insightService.piiProtectionEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: insightService.piiProtectionEnabled) { _ in
                    Task { await insightService.applyPIIRedaction() }
                }
        }
        .padding(12)
        .background(
            insightService.piiProtectionEnabled
                ? Color.green.opacity(0.05)
                : Color.red.opacity(0.05)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    insightService.piiProtectionEnabled
                        ? Color.green.opacity(0.2)
                        : Color.red.opacity(0.3),
                    lineWidth: 1
                )
        )
        .cornerRadius(8)
    }

    private var redactionSummaryBanner: some View {
        let summary = insightService.redactionSummary
        return HStack(spacing: 8) {
            Image(systemName: summary.hasCriticalItems ? "exclamationmark.shield.fill" : "shield.checkered")
                .foregroundStyle(summary.hasCriticalItems ? .orange : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.formattedSummary)
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
                if summary.hasCriticalItems {
                    Text("Critical items (SSNs, credit cards) were found and redacted. These will NOT be sent to the AI.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(summary.hasCriticalItems ? Color.orange.opacity(0.06) : Color.green.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(summary.hasCriticalItems ? Color.orange.opacity(0.2) : Color.green.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Source Management

    private var sourceManagementSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Document Sources")
                    .font(.headline)
                Spacer()

                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    Task { await insightService.scanAllSources() }
                    Task {
                        let config = LLMProviderConfig(
                            provider: configManager.activeProvider,
                            model: configManager.activeModel,
                            baseURL: configManager.customBaseURL
                        )
                        await chatService.checkModelRecommendation(
                            corpus: insightService.corpus,
                            currentConfig: config
                        )
                    }
                } label: {
                    Label("Scan", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(insightService.sources.isEmpty || insightService.isScanning)
            }

            if insightService.sources.isEmpty {
                HStack {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(Color.dsSecondaryText)
                    VStack(alignment: .leading) {
                        Text("No sources added")
                            .font(.subheadline.bold())
                        Text("Add folders containing your documents to get started.")
                            .font(.caption)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsSecondaryBackground)
                .cornerRadius(8)
            } else {
                VStack(spacing: 4) {
                    ForEach(insightService.sources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
    }

    private func sourceRow(_ source: DocumentSource) -> some View {
        HStack {
            Image(systemName: statusIcon(for: source.scanStatus))
                .foregroundStyle(statusColor(for: source.scanStatus))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.subheadline.bold())
                Text(source.url.path)
                    .font(.caption2)
                    .foregroundStyle(Color.dsTertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            if source.scanStatus == .completed {
                Text("\(source.documentCount) docs")
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Button {
                insightService.removeSource(id: source.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .buttonStyle(.borderless)
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.dsSecondaryBackground)
        .cornerRadius(6)
    }

    // MARK: - Scan Progress

    private var scanProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                if let progress = insightService.scanProgress {
                    Text("Scanning \(progress.current) (\(progress.processed)/\(progress.total))")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                } else {
                    Text("Preparing scan...")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Model Recommendation

    private func modelRecommendationBanner(_ rec: ModelRecommendation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Model Recommendation")
                    .font(.subheadline.bold())
                Text(rec.reason)
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Spacer()

            if rec.isInstalled {
                Button("Switch") {
                    // Model switching handled by config manager
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if let cmd = rec.pullCommand {
                Button("Pull & Switch") {
                    // Pull model via ollama
                    _ = cmd
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                chatService.dismissModelRecommendation()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        .cornerRadius(8)
    }

    private func modelRecommendationBadge(_ rec: ModelRecommendation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.caption)
            Text(rec.recommendedModel)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Document Inventory

    private var documentInventorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Document Inventory")
                    .font(.headline)
                Spacer()
                Text("\(insightService.corpus.supportedFileCount) files")
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
                if insightService.corpus.ocrDocCount > 0 {
                    Text("(\(insightService.corpus.ocrDocCount) OCR)")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }

            LazyVStack(spacing: 2) {
                HStack {
                    Text("File").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Type").font(.caption.bold()).frame(width: 50)
                    Text("Chars").font(.caption.bold()).frame(width: 60)
                    Text("Method").font(.caption.bold()).frame(width: 70)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.dsSecondaryBackground)

                ForEach(insightService.corpus.successfulDocuments.prefix(100)) { doc in
                    HStack {
                        Text(doc.fileName)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(doc.fileType.uppercased())
                            .font(.caption2)
                            .frame(width: 50)
                        Text(doc.formattedCharCount)
                            .font(.caption)
                            .frame(width: 60)
                        Text(doc.extractionMethod.displayName)
                            .font(.caption2)
                            .foregroundStyle(doc.extractionMethod.isOCR ? Color.orange : Color.dsSecondaryText)
                            .frame(width: 70)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .background(Color.dsSecondaryBackground.opacity(0.5))
            .cornerRadius(6)
        }
    }

    // MARK: - Data Points Table

    private func dataPointsSection(_ result: InsightResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Extracted Data Points")
                    .font(.headline)
                Spacer()

                Button {
                    showExportOptions = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .popover(isPresented: $showExportOptions) {
                    exportPopover(result: result)
                }
            }

            LazyVStack(spacing: 2) {
                HStack {
                    Text("Item").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value").font(.caption.bold()).frame(width: 120, alignment: .trailing)
                    Text("Source").font(.caption.bold()).frame(width: 120)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.dsSecondaryBackground)

                ForEach(result.dataPoints) { dp in
                    HStack {
                        Text(dp.label)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(dp.value)
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .trailing)
                        Text(dp.sourceDocument)
                            .font(.caption2)
                            .foregroundStyle(Color.dsSecondaryText)
                            .lineLimit(1)
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .background(Color.dsSecondaryBackground.opacity(0.5))
            .cornerRadius(6)
        }
    }

    // MARK: - Export Popover

    private func exportPopover(result: InsightResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Results")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(ReportFormat.allCases) { format in
                Button {
                    Task {
                        await exportResult(result: result, format: format)
                    }
                    showExportOptions = false
                } label: {
                    Label(format.displayName, systemImage: format.icon)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        AIChatPanelView(
            title: "Ask My Docs",
            placeholder: "Ask about your documents...",
            messages: chatService.messages,
            input: $chatInput,
            isLoading: chatService.isLoading,
            quickActions: quickActions,
            onSend: {
                let text = chatInput
                chatInput = ""
                Task {
                    await chatService.send(
                        text: text,
                        insightService: insightService,
                        configManager: configManager
                    )
                }
            },
            onClose: { showChatPanel = false }
        )
    }

    private var quickActions: [String] {
        if insightService.corpus.successfulDocuments.isEmpty {
            return ["help"]
        }

        switch insightService.corpus.detectedDomain {
        case .financial:
            return ["Summarize all expenses", "List income sources", "Find tax deductions", "show documents"]
        case .legal:
            return ["Key terms and obligations", "List all parties", "Important dates", "show documents"]
        case .medical:
            return ["List all diagnoses", "Medication summary", "Insurance claims", "show documents"]
        default:
            return ["Summarize all documents", "List key data points", "show documents"]
        }
    }

    // MARK: - Actions

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select folders containing documents to analyze"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            insightService.addSource(url: url)
        }
    }

    private func exportResult(result: InsightResult, format: ReportFormat) async {
        let genService = DocumentGenerationService()
        do {
            let data = try await genService.generateInsightReport(
                result: result,
                query: chatService.messages.last(where: { $0.role == "user" })?.text ?? "Document Analysis",
                corpus: insightService.corpus,
                format: format
            )
            await saveData(data, defaultName: "document_analysis.\(format.fileExtension)", format: format)
        } catch {
            chatService.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func saveData(_ data: Data, defaultName: String, format: ReportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        switch format {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
        case .markdown:
            panel.allowedContentTypes = [.plainText]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    // MARK: - Helpers

    private func statusIcon(for status: ScanStatus) -> String {
        switch status {
        case .pending: return "circle.dashed"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(for status: ScanStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .scanning: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }
}
