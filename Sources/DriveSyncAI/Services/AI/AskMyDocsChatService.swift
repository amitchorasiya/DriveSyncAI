// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import SwiftUI

@MainActor
final class AskMyDocsChatService: ObservableObject {

    @Published var messages: [OrganizationChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastInsightResult: InsightResult?
    @Published var lastTaxReviewResult: TaxReviewResult?
    @Published var modelRecommendation: ModelRecommendation?

    private var conversationHistory: [(role: String, text: String)] = []
    private let modelAdvisor = ModelAdvisorService()
    private let taxReviewService = TaxReviewService()
    private let maxHistoryTurns = 5

    // MARK: - Initialization

    func addWelcomeMessage() {
        guard messages.isEmpty else { return }
        messages.append(OrganizationChatMessage(
            role: "assistant",
            text: "Welcome to Ask My Docs! Add source folders containing your documents, then scan them. Once scanned, you can ask me questions about your documents — I'll extract text, analyze content, and find the information you need.\n\nTry asking things like:\n• \"What were my total expenses?\"\n• \"List all income sources with amounts\"\n• \"Summarize the key terms of this contract\""
        ))
    }

    // MARK: - Document Q&A

    func send(
        text: String,
        insightService: DocumentInsightService,
        configManager: LLMConfigManager
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(OrganizationChatMessage(role: "user", text: trimmed))
        conversationHistory.append((role: "user", text: trimmed))
        trimHistory()

        if let localResponse = tryLocalCommand(trimmed, corpus: insightService.corpus) {
            messages.append(OrganizationChatMessage(role: "assistant", text: localResponse))
            conversationHistory.append((role: "assistant", text: localResponse))
            return
        }

        guard !insightService.corpus.successfulDocuments.isEmpty else {
            let msg: String
            if insightService.hasCompletedScan {
                let totalFiles = insightService.corpus.documents.count
                if totalFiles > 0 {
                    msg = "The scan found \(totalFiles) file(s) but none could be read. They may be encrypted, corrupted, or in an unsupported format. Supported formats: PDF, images (JPG/PNG), DOCX, Excel (XLSX), CSV, and plain text."
                } else {
                    msg = "The scan completed but no files were found in the selected folders. Please check that the folders contain documents and try again."
                }
            } else {
                msg = "No documents have been scanned yet. Please add source folders and click **Scan** first."
            }
            messages.append(OrganizationChatMessage(role: "assistant", text: msg))
            return
        }

        isLoading = true
        lastError = nil

        do {
            let result = try await insightService.query(
                question: trimmed,
                conversationHistory: conversationHistory,
                configManager: configManager
            )

            lastInsightResult = result
            var responseText = result.answer

            if !result.dataPoints.isEmpty {
                responseText += "\n\n**Extracted Data:**\n"
                for dp in result.dataPoints {
                    responseText += "• **\(dp.label)**: \(dp.value)"
                    responseText += " _(from \(dp.sourceDocument))_\n"
                }
            }

            if let note = result.completenessNote {
                responseText += "\n> \(note)"
            }

            if !result.suggestedFollowUps.isEmpty {
                responseText += "\n\n**You might also ask:**\n"
                for q in result.suggestedFollowUps.prefix(3) {
                    responseText += "• \(q)\n"
                }
            }

            messages.append(OrganizationChatMessage(role: "assistant", text: responseText))
            conversationHistory.append((role: "assistant", text: result.answer))

        } catch {
            if isContextSizeExceeded(error) {
                let reducedHistory = Array(conversationHistory.suffix(2))
                if !reducedHistory.isEmpty {
                    do {
                        let result = try await insightService.query(
                            question: trimmed,
                            conversationHistory: [],
                            configManager: configManager
                        )
                        lastInsightResult = result
                        var responseText = result.answer
                        if !result.dataPoints.isEmpty {
                            responseText += "\n\n**Extracted Data:**\n"
                            for dp in result.dataPoints {
                                responseText += "• **\(dp.label)**: \(dp.value)"
                                responseText += " _(from \(dp.sourceDocument))_\n"
                            }
                        }
                        if let note = result.completenessNote {
                            responseText += "\n\n> \(note)"
                        }
                        if !result.suggestedFollowUps.isEmpty {
                            responseText += "\n\n**You might also ask:**\n"
                            for q in result.suggestedFollowUps.prefix(3) {
                                responseText += "• \(q)\n"
                            }
                        }
                        messages.append(OrganizationChatMessage(role: "assistant", text: responseText))
                        conversationHistory.append((role: "assistant", text: result.answer))
                        messages.append(OrganizationChatMessage(
                            role: "system",
                            text: "The previous reply was sent using only this question (conversation history was trimmed to fit the model's context window).",
                            isStatusMessage: true
                        ))
                        isLoading = false
                        return
                    } catch _ { }
                }
                lastError = "Context size exceeded"
                messages.append(OrganizationChatMessage(
                    role: "system",
                    text: "**Context limit reached.** The conversation and documents don't fit in this model's context window. Try: 1) **Start a new chat** (clear history and ask again), 2) **Switch to a model with a larger context** in Settings (e.g. Gemma 3 12B), or 3) Ask a more focused question.",
                    isStatusMessage: true
                ))
            } else {
                lastError = error.localizedDescription
                messages.append(OrganizationChatMessage(
                    role: "system",
                    text: "Error: \(error.localizedDescription)",
                    isStatusMessage: true
                ))
            }
        }

        isLoading = false
    }

    private func isContextSizeExceeded(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("exceed_context_size")
            || msg.contains("exceeds the available context size")
            || msg.contains("context size")
            || (msg.contains("n_ctx") && msg.contains("token"))
    }

    // MARK: - Tax Review

    func runTaxReview(
        draftDocument: DocumentContent,
        corpus: DocumentCorpus,
        priorYearDraft: DocumentContent?,
        configManager: LLMConfigManager
    ) async {
        isLoading = true
        lastError = nil

        messages.append(OrganizationChatMessage(
            role: "system",
            text: "Starting tax document review of \(draftDocument.fileName)...",
            isStatusMessage: true
        ))

        do {
            let result = try await taxReviewService.reviewDraft(
                draftDocument: draftDocument,
                corpus: corpus,
                priorYearDraft: priorYearDraft,
                configManager: configManager
            )

            lastTaxReviewResult = result

            var summary = "**Tax Review Complete** — Score: \(result.overallScore)/100 | Risk Level: \(result.auditRiskLevel.displayName)\n\n"

            if result.verifiedCount > 0 {
                summary += "✓ \(result.verifiedCount) line items verified against source documents\n"
            }
            if result.discrepancyCount > 0 {
                summary += "⚠ \(result.discrepancyCount) discrepancies detected\n"
            }
            if !result.savingsFindings.isEmpty {
                summary += "💡 \(result.savingsFindings.count) areas to review with your tax preparer\n"
                if let total = result.totalPotentialSavings {
                    summary += "   Estimated potential: \(total) — verify with CPA\n"
                }
            }
            if !result.auditRiskFindings.isEmpty {
                summary += "📋 \(result.auditRiskFindings.count) items that may warrant additional documentation\n"
            }
            if !result.yoyFindings.isEmpty {
                summary += "📊 \(result.yoyFindings.count) year-over-year changes noted\n"
            }

            summary += "\n_\(TaxReviewResult.shortDisclaimer)_"
            summary += "\n\nYou can ask me follow-up questions about any of these findings."

            messages.append(OrganizationChatMessage(role: "assistant", text: summary))

        } catch {
            lastError = error.localizedDescription
            var failureText = "Tax review failed: \(error.localizedDescription)"
            if isContextSizeExceeded(error) {
                failureText += "\n\n**Tip:** Your document is large. Use a model with a larger context (e.g. **mistral-nemo** 128K) in Settings → AI Provider for full-document review. The review will still use the first portion of your draft with the current model."
            }
            messages.append(OrganizationChatMessage(
                role: "system",
                text: failureText,
                isStatusMessage: true
            ))
        }

        isLoading = false
    }

    // MARK: - Scan Notifications

    func notifyScanResult(successCount: Int, failedCount: Int) {
        let msg: String
        if successCount > 0 && failedCount == 0 {
            let plural = successCount == 1 ? "document" : "documents"
            msg = "Scan complete — **\(successCount) \(plural)** loaded and ready. You can now ask questions about your documents."
        } else if successCount > 0 && failedCount > 0 {
            let sPlural = successCount == 1 ? "document" : "documents"
            let fPlural = failedCount == 1 ? "file" : "files"
            msg = "Scan complete — **\(successCount) \(sPlural)** loaded. \(failedCount) \(fPlural) couldn't be read (unsupported format or encrypted). You can ask questions about the loaded documents."
        } else if failedCount > 0 {
            let fPlural = failedCount == 1 ? "file was" : "files were"
            msg = "Scan finished but **no readable documents** were found. \(failedCount) \(fPlural) skipped (unsupported format, encrypted, or empty). Try adding folders with PDFs, images, text files, DOCX, or Excel files."
        } else {
            msg = "Scan finished but **no files** were found in the selected folders. Make sure the folders contain documents and try again."
        }
        messages.append(OrganizationChatMessage(
            role: "system",
            text: msg,
            isStatusMessage: true
        ))
    }

    // MARK: - Model Recommendation

    func checkModelRecommendation(
        corpus: DocumentCorpus,
        currentConfig: LLMProviderConfig,
        insightService: DocumentInsightService? = nil
    ) async {
        let (domain, confidence) = await modelAdvisor.detectDomain(from: corpus)

        if let service = insightService {
            service.corpus.detectedDomain = domain
            service.corpus.domainConfidence = confidence
        }

        if let recommendation = await modelAdvisor.recommend(
            domain: domain,
            corpusStats: corpus,
            currentConfig: currentConfig
        ) {
            modelRecommendation = recommendation

            let msg = "Your documents appear to be **\(domain.displayName)** related. " +
                "For better results, consider switching to **\(recommendation.recommendedModel)**. " +
                recommendation.reason

            messages.append(OrganizationChatMessage(
                role: "system",
                text: msg,
                isStatusMessage: true
            ))
        }
    }

    func dismissModelRecommendation() {
        modelRecommendation = nil
    }

    // MARK: - Local Commands

    private func tryLocalCommand(_ text: String, corpus: DocumentCorpus?) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower == "show documents" || lower == "list files" || lower == "list documents" {
            return formatDocumentList(corpus)
        }

        if lower == "show sources" || lower == "list sources" {
            return formatSourceList(corpus)
        }

        if lower == "show findings" || lower == "show results" {
            if let result = lastTaxReviewResult {
                return formatTaxFindings(result)
            }
            if let result = lastInsightResult {
                return formatInsightSummary(result)
            }
            return "No results available yet. Ask a question about your documents first."
        }

        if lower == "help" {
            return """
            **Available Commands:**
            • **show documents** — List all scanned documents
            • **show sources** — List source folders
            • **show findings** — Show latest analysis results
            • **help** — Show this help message

            Or just ask a question about your documents!
            """
        }

        return nil
    }

    private func formatDocumentList(_ corpus: DocumentCorpus?) -> String {
        guard let corpus = corpus, !corpus.documents.isEmpty else {
            return "No documents scanned yet. Add source folders and click Scan."
        }

        var text = "**Scanned Documents (\(corpus.supportedFileCount) files, \(corpus.totalChars) chars):**\n\n"
        text += "| File | Type | Chars | Method |\n"
        text += "|------|------|-------|--------|\n"

        for doc in corpus.successfulDocuments.prefix(50) {
            text += "| \(doc.fileName) | \(doc.fileType.uppercased()) | \(doc.formattedCharCount) | \(doc.extractionMethod.displayName) |\n"
        }

        if corpus.successfulDocuments.count > 50 {
            text += "\n_... and \(corpus.successfulDocuments.count - 50) more_"
        }

        return text
    }

    private func formatSourceList(_ corpus: DocumentCorpus?) -> String {
        guard let corpus = corpus, !corpus.sources.isEmpty else {
            return "No source folders added yet."
        }

        var text = "**Source Folders (\(corpus.sources.count)):**\n\n"
        for source in corpus.sources {
            text += "• **\(source.displayName)** — \(source.documentCount) docs, \(source.totalChars) chars [\(source.scanStatus.rawValue)]\n"
        }
        return text
    }

    private func formatTaxFindings(_ result: TaxReviewResult) -> String {
        var text = "**Tax Review Summary — Score: \(result.overallScore)/100**\n\n"
        text += "Verified: \(result.verifiedCount) | Discrepancies: \(result.discrepancyCount) | "
        text += "Savings opportunities: \(result.savingsFindings.count) | Documentation items: \(result.auditRiskFindings.count)\n\n"

        for finding in result.findings.prefix(20) {
            let prefix: String
            switch finding.type {
            case .verified: prefix = "✓"
            case .discrepancy: prefix = "⚠"
            case .savingsOpportunity: prefix = "💡"
            case .auditRisk: prefix = "📋"
            case .yearOverYear: prefix = "📊"
            }
            text += "\(prefix) [\(finding.severity.displayName)] \(finding.description)\n"
        }

        text += "\n_\(TaxReviewResult.shortDisclaimer)_"
        return text
    }

    private func formatInsightSummary(_ result: InsightResult) -> String {
        var text = "**Latest Analysis:**\n\n\(result.answer)\n\n"
        if !result.dataPoints.isEmpty {
            text += "**Data Points:** \(result.dataPoints.count) extracted\n"
        }
        return text
    }

    // MARK: - Helpers

    private func trimHistory() {
        if conversationHistory.count > maxHistoryTurns * 2 {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
        }
    }

    func clearChat() {
        messages.removeAll()
        conversationHistory.removeAll()
        lastInsightResult = nil
        lastTaxReviewResult = nil
        lastError = nil
        addWelcomeMessage()
    }
}
