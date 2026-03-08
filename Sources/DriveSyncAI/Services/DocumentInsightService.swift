// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import SwiftUI

@MainActor
final class DocumentInsightService: ObservableObject {

    @Published var corpus = DocumentCorpus()
    @Published var sources: [DocumentSource] = []
    @Published var isScanning = false
    @Published var hasCompletedScan = false
    @Published var scanProgress: (current: String, processed: Int, total: Int)?
    @Published var lastError: String?
    @Published var piiProtectionEnabled = true
    @Published var piiSensitivityLevel: PIISensitivityLevel = .standard
    @Published var redactionSummary = RedactionSummary()
    /// When true, user selected Presidio but it was unavailable so regex was used.
    @Published var presidioFallbackUsed = false

    private let extractor = DocumentTextExtractor()
    private let maxSinglePromptChars = 50_000
    private var redactedDocumentsCache: [DocumentContent] = []

    // MARK: - Source Management

    func addSource(url: URL) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        sources.append(DocumentSource(url: url))
    }

    func removeSource(id: UUID) {
        sources.removeAll { $0.id == id }
        corpus.documents.removeAll { doc in
            !sources.contains(where: { $0.url == doc.sourceFolder })
        }
        recalculateCorpusStats()
    }

    // MARK: - Scanning

    func scanAllSources() async {
        isScanning = true
        lastError = nil
        let startTime = Date()

        var allDocuments: [DocumentContent] = []
        var totalSupported = 0
        var totalUnsupported = 0
        var totalOCR = 0

        for i in 0..<sources.count {
            sources[i].scanStatus = .scanning
            do {
                let docs = try await scanFolder(sources[i].url)
                allDocuments.append(contentsOf: docs)

                let successful = docs.filter(\.isSuccessful)
                sources[i].documentCount = successful.count
                sources[i].totalChars = successful.reduce(0) { $0 + $1.charCount }
                sources[i].scanStatus = successful.isEmpty ? .completedEmpty : .completed

                totalSupported += docs.filter(\.isSuccessful).count
                totalUnsupported += docs.filter { !$0.isSuccessful }.count
                totalOCR += docs.filter { $0.extractionMethod.isOCR }.count
            } catch {
                sources[i].scanStatus = .failed
                sources[i].errorMessage = error.localizedDescription
            }
        }

        corpus.sources = sources
        corpus.documents = allDocuments
        corpus.totalChars = allDocuments.filter(\.isSuccessful).reduce(0) { $0 + $1.charCount }
        corpus.supportedFileCount = totalSupported
        corpus.unsupportedFileCount = totalUnsupported
        corpus.ocrDocCount = totalOCR
        corpus.scanDuration = Date().timeIntervalSince(startTime)

        await applyPIIRedaction()

        hasCompletedScan = true
        isScanning = false
        scanProgress = nil
    }

    func applyPIIRedaction() async {
        if piiProtectionEnabled {
            let engine = PIIEngine(rawValue: UserDefaults.standard.string(forKey: "piiEngine") ?? "") ?? .regex
            presidioFallbackUsed = (engine == .presidio && !PresidioSetupService.isPresidioAvailable)
            let redactor = makePIIRedactor(engine: engine, sensitivity: piiSensitivityLevel)
            let (redacted, summary) = await redactor.redactCorpus(documents: corpus.documents)
            redactedDocumentsCache = redacted
            redactionSummary = summary
        } else {
            presidioFallbackUsed = false
            redactedDocumentsCache = corpus.documents
            redactionSummary = RedactionSummary()
        }
    }

    var documentsForLLM: [DocumentContent] {
        piiProtectionEnabled ? redactedDocumentsCache : corpus.documents
    }

    private func scanFolder(_ folder: URL) async throws -> [DocumentContent] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw DocumentInsightError.cannotAccessFolder(folder.path)
        }

        var urls: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true {
                urls.append(url)
            }
        }

        var documents: [DocumentContent] = []
        for (index, url) in urls.enumerated() {
            scanProgress = (current: url.lastPathComponent, processed: index + 1, total: urls.count)
            let doc = await extractor.extractText(from: url, sourceFolder: folder)
            documents.append(doc)
        }

        return documents
    }

    // MARK: - Query

    func query(
        question: String,
        conversationHistory: [(role: String, text: String)],
        configManager: LLMConfigManager
    ) async throws -> InsightResult {
        let safeDocs = documentsForLLM.filter(\.isSuccessful)
        guard !safeDocs.isEmpty else {
            throw DocumentInsightError.noDocuments
        }

        let service = configManager.currentService()

        if corpus.isLargeCorpus {
            return try await queryMapReduce(
                question: question,
                documents: safeDocs,
                history: conversationHistory,
                service: service
            )
        } else {
            return try await querySinglePass(
                question: question,
                documents: safeDocs,
                history: conversationHistory,
                service: service
            )
        }
    }

    private func querySinglePass(
        question: String,
        documents: [DocumentContent],
        history: [(role: String, text: String)],
        service: LLMServiceProtocol
    ) async throws -> InsightResult {
        let systemPrompt = buildSystemPrompt(domain: corpus.detectedDomain)
        let userPrompt = buildDocumentPrompt(documents: documents, question: question, history: history)

        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseInsightResponse(response)
    }

    private func queryMapReduce(
        question: String,
        documents: [DocumentContent],
        history: [(role: String, text: String)],
        service: LLMServiceProtocol
    ) async throws -> InsightResult {
        var summaries: [(fileName: String, summary: String)] = []

        for doc in documents {
            let truncated = String(doc.extractedText.prefix(10_000))
            let mapPrompt = """
            Analyze the following document and extract information relevant to this question: "\(question)"

            Document: \(doc.fileName)
            Content:
            \(truncated)

            Respond with a brief summary of relevant information found. If nothing relevant, respond with "No relevant information."
            """

            let summary = try await service.sendPrompt(
                system: "You are a document analysis assistant. Extract only information relevant to the user's question.",
                user: mapPrompt
            )

            if !summary.lowercased().contains("no relevant information") {
                summaries.append((fileName: doc.fileName, summary: summary))
            }
        }

        guard !summaries.isEmpty else {
            return InsightResult(
                answer: "I reviewed all \(documents.count) documents but could not find information directly relevant to your question. Try rephrasing or check if the relevant documents are included in your sources.",
                completenessNote: "No relevant content found across \(documents.count) documents."
            )
        }

        let reducePrompt = buildReducePrompt(summaries: summaries, question: question, history: history)
        let systemPrompt = buildSystemPrompt(domain: corpus.detectedDomain)
        let response = try await service.sendPrompt(system: systemPrompt, user: reducePrompt)
        return parseInsightResponse(response)
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(domain: DocumentDomain) -> String {
        var prompt = """
        You are a document analysis assistant. The user has provided documents from one or more folders. \
        Your job is to extract structured information based on their question.

        Rules:
        - For each data point, cite the source document filename
        - Format financial amounts clearly with currency symbols
        - If information seems incomplete, mention what documents might be missing
        - Present data in a clear, organized manner
        - When showing multiple data points, use a structured format

        """

        if piiProtectionEnabled {
            prompt += """

            IMPORTANT: Sensitive personal information (SSNs, account numbers, etc.) has been automatically \
            redacted from the documents for privacy. You will see placeholders like [SSN REDACTED], \
            [ACCOUNT REDACTED], etc. Do NOT attempt to guess, reconstruct, or reference the original values. \
            Work only with the non-redacted information available.

            """
        }

        switch domain {
        case .financial:
            prompt += """
            The documents appear to be financial/tax related. Pay special attention to:
            - Amounts, dates, account numbers, tax form references
            - Income sources, deductions, credits, tax payments
            - Transaction details, balances, interest rates
            - IRS form numbers (W-2, 1099, 1098, etc.)
            Format all monetary amounts with $ and proper comma separation.
            """
        case .legal:
            prompt += """
            The documents appear to be legal in nature. Pay special attention to:
            - Parties involved, dates, obligations, conditions
            - Key clauses, terms, deadlines
            - Jurisdictions, signatures, notarizations
            """
        case .medical:
            prompt += """
            The documents appear to be medical in nature. Pay special attention to:
            - Patient information, dates of service, providers
            - Diagnoses, procedures, medications, dosages
            - Insurance details, claim amounts, copays
            """
        default:
            break
        }

        prompt += """

        Respond in this JSON format:
        {
            "answer": "Your detailed natural language answer here",
            "dataPoints": [
                {"label": "Key name", "value": "Extracted value", "category": "Optional category", "sourceDocument": "filename.pdf", "pageReference": "Page X", "confidence": 0.9}
            ],
            "supportingDocuments": ["filename1.pdf", "filename2.pdf"],
            "suggestedFollowUps": ["Follow-up question 1", "Follow-up question 2"],
            "completenessNote": "Optional note about missing information"
        }
        """

        return prompt
    }

    private func buildDocumentPrompt(
        documents: [DocumentContent],
        question: String,
        history: [(role: String, text: String)]
    ) -> String {
        var prompt = "Documents:\n\n"

        for (index, doc) in documents.enumerated() {
            let truncated = String(doc.extractedText.prefix(maxSinglePromptChars / max(documents.count, 1)))
            let pageInfo = doc.pageCount.map { " (\($0) pages)" } ?? ""
            let ocrNote = doc.extractionMethod.isOCR ? " [OCR]" : ""
            prompt += "[\(index + 1)] \(doc.fileName)\(pageInfo)\(ocrNote):\n\(truncated)\n\n"
        }

        if !history.isEmpty {
            prompt += "Previous conversation:\n"
            for turn in history.suffix(5) {
                prompt += "\(turn.role): \(turn.text)\n"
            }
            prompt += "\n"
        }

        prompt += "Question: \(question)"
        return prompt
    }

    private func buildReducePrompt(
        summaries: [(fileName: String, summary: String)],
        question: String,
        history: [(role: String, text: String)]
    ) -> String {
        var prompt = "I analyzed \(summaries.count) relevant documents. Here are the summaries:\n\n"

        for (index, s) in summaries.enumerated() {
            prompt += "[\(index + 1)] \(s.fileName):\n\(s.summary)\n\n"
        }

        if !history.isEmpty {
            prompt += "Previous conversation:\n"
            for turn in history.suffix(5) {
                prompt += "\(turn.role): \(turn.text)\n"
            }
            prompt += "\n"
        }

        prompt += "Based on all these document summaries, please answer: \(question)"
        return prompt
    }

    // MARK: - Response Parsing

    private func parseInsightResponse(_ response: String) -> InsightResult {
        if let jsonData = extractJSON(from: response),
           let parsed = try? JSONDecoder().decode(InsightResponseJSON.self, from: jsonData) {
            return InsightResult(
                answer: parsed.answer,
                dataPoints: parsed.dataPoints?.map { dp in
                    ExtractedDataPoint(
                        label: dp.label,
                        value: dp.value,
                        category: dp.category,
                        sourceDocument: dp.sourceDocument,
                        pageReference: dp.pageReference,
                        confidence: dp.confidence ?? 0.8
                    )
                } ?? [],
                supportingDocuments: parsed.supportingDocuments ?? [],
                suggestedFollowUps: parsed.suggestedFollowUps ?? [],
                completenessNote: parsed.completenessNote
            )
        }

        return InsightResult(answer: response)
    }

    private func extractJSON(from text: String) -> Data? {
        if let range = text.range(of: "```json") {
            let start = range.upperBound
            if let endRange = text.range(of: "```", range: start..<text.endIndex) {
                let jsonString = String(text[start..<endRange.lowerBound])
                return jsonString.data(using: .utf8)
            }
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let jsonString = String(text[start...end])
            return jsonString.data(using: .utf8)
        }

        return nil
    }

    // MARK: - Helpers

    private func recalculateCorpusStats() {
        let docs = corpus.documents.filter(\.isSuccessful)
        corpus.totalChars = docs.reduce(0) { $0 + $1.charCount }
        corpus.supportedFileCount = docs.count
        corpus.ocrDocCount = docs.filter { $0.extractionMethod.isOCR }.count
    }
}

// MARK: - JSON Response Models

private struct InsightResponseJSON: Decodable {
    var answer: String
    var dataPoints: [DataPointJSON]?
    var supportingDocuments: [String]?
    var suggestedFollowUps: [String]?
    var completenessNote: String?
}

private struct DataPointJSON: Decodable {
    var label: String
    var value: String
    var category: String?
    var sourceDocument: String
    var pageReference: String?
    var confidence: Double?
}

// MARK: - Errors

enum DocumentInsightError: LocalizedError {
    case cannotAccessFolder(String)
    case noDocuments
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotAccessFolder(let path): return "Cannot access folder: \(path)"
        case .noDocuments: return "No documents have been scanned. Add source folders and scan first."
        case .queryFailed(let msg): return "Query failed: \(msg)"
        }
    }
}
