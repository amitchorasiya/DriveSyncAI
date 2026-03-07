// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import UniformTypeIdentifiers

struct TaxReviewView: View {
    @ObservedObject var insightService: DocumentInsightService
    @ObservedObject var chatService: AskMyDocsChatService
    var configManager: LLMConfigManager

    @State private var draftDocument: DocumentContent?
    @State private var priorYearDocument: DocumentContent?
    @State private var isReviewing = false
    @State private var showExportOptions = false
    @AppStorage("hasAcceptedTaxDisclaimer") private var hasAcceptedTaxDisclaimer = false
    @State private var showDisclaimerGate = false
    @State private var detectedPIITypes: [PIIType] = []
    @State private var showPIIWarning = false

    private let extractor = DocumentTextExtractor()
    private let taxService = TaxReviewService()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            if !hasAcceptedTaxDisclaimer {
                disclaimerGate
            } else {
                disclaimerBanner
                reviewContent
            }
        }
    }

    // MARK: - Disclaimer Gate

    private var disclaimerGate: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Tax Document Review")
                .font(.title2.bold())

            Text(TaxReviewResult.fullDisclaimer)
                .font(.callout)
                .foregroundStyle(Color.dsSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                hasAcceptedTaxDisclaimer = true
            } label: {
                Text("I understand this is informational only and not tax advice")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Persistent Disclaimer Banner

    private var disclaimerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text(TaxReviewResult.shortDisclaimer)
                .font(.caption)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        .cornerRadius(6)
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            piiProtectionBanner
            if showPIIWarning {
                piiWarningBanner
            }
            sourceDocumentsStatus
            draftUploadSection
            priorYearSection
            runReviewButton

            if let result = chatService.lastTaxReviewResult {
                findingsDashboard(result)
            }
        }
    }

    // MARK: - PII Protection Banner

    private var piiProtectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("PII Protection: Always ON for Tax Review")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Text("SSNs, account numbers, and other sensitive data are automatically redacted before being sent to the AI model. This cannot be disabled for tax documents.")
                    .font(.caption2)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
        .cornerRadius(6)
    }

    private var piiWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sensitive Data Detected in Draft")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                let typeNames = detectedPIITypes.map(\.displayName).joined(separator: ", ")
                Text("Found: \(typeNames). These will be automatically redacted before analysis. The AI model will only see redacted placeholders.")
                    .font(.caption2)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            Spacer()
            Button {
                showPIIWarning = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .cornerRadius(6)
    }

    // MARK: - Source Documents Status

    private var sourceDocumentsStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step 1: Source Documents")
                .font(.subheadline.bold())

            if insightService.corpus.successfulDocuments.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No source documents scanned. Go to the Ask tab and add folders with your W-2s, 1099s, receipts, etc.")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(insightService.corpus.supportedFileCount) documents from \(insightService.corpus.sources.count) source(s)")
                        .font(.caption)
                    Text("| Domain: \(insightService.corpus.detectedDomain.displayName)")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
        }
    }

    // MARK: - Draft Upload

    private var draftUploadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step 2: Upload Draft Tax Return")
                .font(.subheadline.bold())

            if let draft = draftDocument {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(Color.dsPrimary)
                    VStack(alignment: .leading) {
                        Text(draft.fileName)
                            .font(.caption.bold())
                        Text("\(draft.pageCount ?? 0) pages | \(draft.formattedCharCount) chars | \(draft.extractionMethod.displayName)")
                            .font(.caption2)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    Spacer()
                    Button {
                        draftDocument = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                    .background(Color.dsPrimary.opacity(0.05))
                .cornerRadius(6)
            } else {
                Button {
                    uploadDraft()
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                        Text("Select draft tax return (PDF, DOCX)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.dsSecondaryBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(Color.dsSecondaryText.opacity(0.3)))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Prior Year

    private var priorYearSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step 3: Prior Year Return (Optional)")
                .font(.subheadline.bold())
            Text("For year-over-year comparison")
                .font(.caption2)
                .foregroundStyle(Color.dsTertiaryText)

            if let prior = priorYearDocument {
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(Color.dsSecondaryText)
                    Text(prior.fileName)
                        .font(.caption)
                    Spacer()
                    Button {
                        priorYearDocument = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.dsSecondaryBackground)
                .cornerRadius(6)
            } else {
                Button {
                    uploadPriorYear()
                } label: {
                    Label("Add prior year return", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Run Review

    private var runReviewButton: some View {
        Button {
            Task {
                isReviewing = true
                await chatService.runTaxReview(
                    draftDocument: draftDocument!,
                    corpus: insightService.corpus,
                    priorYearDraft: priorYearDocument,
                    configManager: configManager
                )
                isReviewing = false
            }
        } label: {
            HStack {
                if isReviewing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Reviewing...")
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Run Tax Review")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(draftDocument == nil || insightService.corpus.successfulDocuments.isEmpty || isReviewing)
    }

    // MARK: - Findings Dashboard

    private func findingsDashboard(_ result: TaxReviewResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Divider()

            HStack(spacing: AppTheme.Spacing.xl) {
                scoreBadge(score: result.overallScore)
                riskBadge(level: result.auditRiskLevel)
                Spacer()
                exportButton(result)
            }

            if !result.accuracyFindings.isEmpty {
                findingsSection(
                    title: "Accuracy Check (\(result.verifiedCount) verified, \(result.discrepancyCount) discrepancies)",
                    icon: "checkmark.shield",
                    findings: result.accuracyFindings
                )
            }

            if !result.savingsFindings.isEmpty {
                findingsSection(
                    title: "Areas to Review With Your Tax Preparer (\(result.savingsFindings.count))",
                    icon: "lightbulb",
                    findings: result.savingsFindings,
                    showSavings: true
                )
            }

            if !result.auditRiskFindings.isEmpty {
                findingsSection(
                    title: "Items That May Warrant Additional Documentation (\(result.auditRiskFindings.count))",
                    icon: "shield.lefthalf.filled",
                    findings: result.auditRiskFindings
                )
            }

            if !result.yoyFindings.isEmpty {
                findingsSection(
                    title: "Year-over-Year Changes (\(result.yoyFindings.count))",
                    icon: "chart.line.uptrend.xyaxis",
                    findings: result.yoyFindings
                )
            }

            disclaimerBanner
        }
    }

    // MARK: - Score and Risk Badges

    private func scoreBadge(score: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(score))
            Text("/ 100")
                .font(.caption2)
                .foregroundStyle(Color.dsSecondaryText)
            Text("Score")
                .font(.caption.bold())
        }
        .padding(16)
        .background(Color.dsSecondaryBackground)
        .cornerRadius(12)
    }

    private func riskBadge(level: AuditRiskLevel) -> some View {
        VStack(spacing: 4) {
            Image(systemName: level.icon)
                .font(.title)
                .foregroundStyle(riskColor(level))
            Text(level.displayName.uppercased())
                .font(.caption.bold())
                .foregroundStyle(riskColor(level))
            Text("Documentation Risk")
                .font(.caption2)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(16)
        .background(Color.dsSecondaryBackground)
        .cornerRadius(12)
    }

    // MARK: - Findings Section

    private func findingsSection(
        title: String,
        icon: String,
        findings: [ReviewFinding],
        showSavings: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.bold())
            }

            VStack(spacing: 2) {
                ForEach(findings) { finding in
                    findingRow(finding, showSavings: showSavings)
                }
            }
            .background(Color.dsSecondaryBackground.opacity(0.5))
            .cornerRadius(6)
        }
    }

    private func findingRow(_ finding: ReviewFinding, showSavings: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: findingIcon(finding))
                .foregroundStyle(findingColor(finding))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(finding.description)
                    .font(.caption)

                HStack(spacing: 12) {
                    if let line = finding.draftLineReference {
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    if let doc = finding.sourceDocument {
                        Text(doc)
                            .font(.caption2)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    if showSavings, let savings = finding.potentialSavings {
                        Text(savings)
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(finding.severity.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(findingColor(finding).opacity(0.1))
                .foregroundStyle(findingColor(finding))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Export

    private func exportButton(_ result: TaxReviewResult) -> some View {
        Menu {
            ForEach(ReportFormat.allCases) { format in
                Button {
                    Task { await exportTaxReview(result: result, format: format) }
                } label: {
                    Label(format.displayName, systemImage: format.icon)
                }
            }
        } label: {
            Label("Export Report", systemImage: "square.and.arrow.up")
        }
    }

    private func exportTaxReview(result: TaxReviewResult, format: ReportFormat) async {
        let genService = DocumentGenerationService()
        do {
            let data = try await genService.generateTaxReviewReport(result: result, format: format)
            await saveData(data, defaultName: "tax_review_report.\(format.fileExtension)", format: format)
        } catch {
            chatService.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func saveData(_ data: Data, defaultName: String, format: ReportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        switch format {
        case .pdf: panel.allowedContentTypes = [.pdf]
        case .csv: panel.allowedContentTypes = [.commaSeparatedText]
        case .markdown: panel.allowedContentTypes = [.plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    // MARK: - File Upload

    private func uploadDraft() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "docx")].compactMap { $0 }
        panel.message = "Select your draft tax return"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let doc = await extractor.extractText(from: url, sourceFolder: url.deletingLastPathComponent())
            draftDocument = doc

            let piiTypes = await taxService.detectPIIInDraft(doc.extractedText)
            if !piiTypes.isEmpty {
                detectedPIITypes = piiTypes
                showPIIWarning = true
            }
        }
    }

    private func uploadPriorYear() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "docx")].compactMap { $0 }
        panel.message = "Select your prior year tax return"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let doc = await extractor.extractText(from: url, sourceFolder: url.deletingLastPathComponent())
            priorYearDocument = doc
        }
    }

    // MARK: - Visual Helpers

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func riskColor(_ level: AuditRiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .yellow
        case .elevated: return .orange
        case .high: return .red
        }
    }

    private func findingIcon(_ finding: ReviewFinding) -> String {
        switch finding.type {
        case .verified: return "checkmark.circle.fill"
        case .discrepancy: return "exclamationmark.triangle.fill"
        case .savingsOpportunity: return "lightbulb.fill"
        case .auditRisk: return "shield.lefthalf.filled"
        case .yearOverYear: return "chart.line.uptrend.xyaxis"
        }
    }

    private func findingColor(_ finding: ReviewFinding) -> Color {
        switch finding.type {
        case .verified: return .green
        case .discrepancy: return .red
        case .savingsOpportunity: return .orange
        case .auditRisk: return .yellow
        case .yearOverYear: return .blue
        }
    }
}
