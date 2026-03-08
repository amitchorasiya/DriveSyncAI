// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor TaxReviewService {

    private func piiRedactor() -> PIIRedactorRef {
        let engine = PIIEngine(rawValue: UserDefaults.standard.string(forKey: "piiEngine") ?? "") ?? .regex
        return makePIIRedactor(engine: engine, sensitivity: .standard)
    }

    // MARK: - Pre-Review PII Check

    func detectPIIInDraft(_ text: String) async -> [PIIType] {
        await piiRedactor().detectPII(in: text)
    }

    // MARK: - Public API

    func reviewDraft(
        draftDocument: DocumentContent,
        corpus: DocumentCorpus,
        priorYearDraft: DocumentContent?,
        configManager: LLMConfigManager
    ) async throws -> TaxReviewResult {
        let startTime = Date()
        let service = await configManager.currentService()
        let redactor = piiRedactor()

        let (safeDraft, _) = await redactor.redactText(
            draftDocument.extractedText, fileName: draftDocument.fileName
        )
        var redactedDraft = draftDocument
        redactedDraft.extractedText = safeDraft

        let (safeCorpusDocs, _) = await redactor.redactCorpus(
            documents: corpus.successfulDocuments
        )
        var safeCorpus = corpus
        safeCorpus.documents = safeCorpusDocs

        var safePriorYear: DocumentContent?
        if let prior = priorYearDraft {
            let (safePrior, _) = await redactor.redactText(
                prior.extractedText, fileName: prior.fileName
            )
            var redactedPrior = prior
            redactedPrior.extractedText = safePrior
            safePriorYear = redactedPrior
        }

        let accuracyFindings = try await runAccuracyCheck(
            draft: redactedDraft, corpus: safeCorpus, service: service
        )

        let savingsFindings = try await runSavingsFinder(
            draft: redactedDraft, corpus: safeCorpus, service: service
        )

        let auditRiskFindings = try await runAuditRiskAssessment(
            draft: redactedDraft, service: service
        )

        var yoyFindings: [ReviewFinding] = []
        if let safePrior = safePriorYear {
            yoyFindings = try await runYearOverYearComparison(
                currentDraft: redactedDraft, priorDraft: safePrior, service: service
            )
        }

        var allFindings = accuracyFindings + savingsFindings + auditRiskFindings + yoyFindings
        let lineItems = extractLineItems(from: accuracyFindings)

        let score = computeOverallScore(findings: allFindings)
        let riskLevel = computeAuditRisk(findings: auditRiskFindings)

        allFindings.sort { $0.severity > $1.severity }

        return TaxReviewResult(
            overallScore: score,
            auditRiskLevel: riskLevel,
            draftDocument: draftDocument.fileName,
            lineItems: lineItems,
            findings: allFindings,
            reviewDuration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Layer 1: Accuracy Check

    private func runAccuracyCheck(
        draft: DocumentContent,
        corpus: DocumentCorpus,
        service: LLMServiceProtocol
    ) async throws -> [ReviewFinding] {
        let sourceDocSummaries = corpus.successfulDocuments.prefix(30).map { doc in
            "[\(doc.fileName)] (\(doc.extractionMethod.displayName)):\n\(String(doc.extractedText.prefix(3000)))"
        }.joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You are a document comparison assistant for US tax returns. You will be given a draft tax return \
        and source documents (W-2s, 1099s, receipts, etc.).

        Your task: Compare the numbers on the draft return against the source documents and identify \
        any discrepancies.

        PRIVACY NOTE: Sensitive personal information (SSNs, account numbers, etc.) has been redacted \
        and replaced with placeholders like [SSN REDACTED]. Do NOT attempt to guess or reconstruct \
        these values. Focus only on financial amounts, line items, and tax-relevant data.

        IMPORTANT LANGUAGE RULES:
        - Use "Your documents indicate..." not "You owe..." or "You should..."
        - Use "Discrepancy detected between documents" not "This is an error"
        - Frame everything as informational comparison, not advice

        Respond in JSON:
        {
            "findings": [
                {
                    "type": "verified" or "discrepancy",
                    "severity": "info" or "low" or "medium" or "high" or "critical",
                    "description": "Clear description of the comparison result",
                    "draftLineReference": "Form 1040 Line 1a",
                    "draftValue": "$95,420",
                    "sourceValue": "$95,420",
                    "sourceDocument": "W-2_2025.pdf",
                    "recommendation": "Optional suggestion to discuss with tax preparer"
                }
            ]
        }
        """

        let userPrompt = """
        Draft tax return (\(draft.fileName)):
        \(String(draft.extractedText.prefix(8000)))

        Source documents:
        \(sourceDocSummaries)

        Compare the draft return line items against the source documents. For each major line item \
        (income, deductions, credits), indicate whether the amounts match or if there is a discrepancy.
        """

        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseFindingsResponse(response)
    }

    // MARK: - Layer 2: Savings Finder

    private func runSavingsFinder(
        draft: DocumentContent,
        corpus: DocumentCorpus,
        service: LLMServiceProtocol
    ) async throws -> [ReviewFinding] {
        let sourceDocNames = corpus.successfulDocuments.map(\.fileName).joined(separator: ", ")
        let sourceDocContent = corpus.successfulDocuments.prefix(20).map { doc in
            "[\(doc.fileName)]:\n\(String(doc.extractedText.prefix(2000)))"
        }.joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You are a tax document review assistant. Review the draft tax return and available source \
        documents to identify potential areas the taxpayer may want to discuss with their tax preparer.

        IMPORTANT LANGUAGE RULES:
        - Use "Your documents include..." not "You are missing..."
        - Use "Consider reviewing with your tax preparer" not "You should claim..."
        - Use "Potential area to review" not "Missed deduction"
        - Always qualify savings estimates with "Up to ~$X — verify with CPA"
        - Frame everything as informational, not advisory

        Common areas to check for US tax returns:
        - HSA contributions (Form 5498-SA -> Line 13)
        - Student loan interest (1098-E -> Line 21)
        - Educator expenses
        - Home office deduction (if Schedule C)
        - State/local tax deduction
        - Energy credits
        - Child tax credit / dependent care
        - Retirement contributions (401k, IRA)
        - Qualified business income deduction (Section 199A)
        - Charitable contributions
        - Itemized vs standard deduction comparison

        Respond in JSON:
        {
            "findings": [
                {
                    "type": "savingsOpportunity",
                    "severity": "low" or "medium" or "high",
                    "description": "Detailed description using informational language",
                    "draftLineReference": "Optional form line reference",
                    "sourceDocument": "Relevant source doc if applicable",
                    "potentialSavings": "Up to ~$X — verify with CPA",
                    "recommendation": "Consider discussing with your tax preparer..."
                }
            ]
        }
        """

        let userPrompt = """
        Draft tax return (\(draft.fileName)):
        \(String(draft.extractedText.prefix(6000)))

        Available source documents: \(sourceDocNames)

        Source document content:
        \(sourceDocContent)

        Identify any areas where the source documents suggest potential deductions or credits \
        that do not appear to be reflected in the draft return.
        """

        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseFindingsResponse(response)
    }

    // MARK: - Layer 3: Audit Risk Assessment

    private func runAuditRiskAssessment(
        draft: DocumentContent,
        service: LLMServiceProtocol
    ) async throws -> [ReviewFinding] {
        let systemPrompt = """
        You are a tax document review assistant. Analyze the draft tax return for items that \
        may warrant additional documentation or attention.

        IMPORTANT LANGUAGE RULES:
        - Use "This item may warrant additional documentation" not "This will trigger an audit"
        - Use "Consider keeping detailed records" not "This is risky"
        - Frame everything as documentation best practices, not warnings
        - Audit likelihood is statistical, never certain

        Common items to review:
        - Schedule C losses exceeding $25K (hobby loss considerations)
        - Charitable deductions exceeding 60% of AGI
        - Home office deduction on Schedule C
        - Round numbers in multiple deduction categories
        - Large unreimbursed employee expenses
        - Significant discrepancy between reported income and lifestyle indicators
        - Crypto/digital asset transactions
        - Large miscellaneous deductions
        - Cash-heavy business income

        Respond in JSON:
        {
            "findings": [
                {
                    "type": "auditRisk",
                    "severity": "info" or "low" or "medium" or "high",
                    "description": "Description using documentation-focused language",
                    "draftLineReference": "Optional form line",
                    "recommendation": "Consider maintaining detailed records for..."
                }
            ]
        }
        """

        let userPrompt = """
        Draft tax return (\(draft.fileName)):
        \(String(draft.extractedText.prefix(8000)))

        Review this draft for items that may benefit from additional documentation or attention.
        """

        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseFindingsResponse(response)
    }

    // MARK: - Layer 4: Year-over-Year

    private func runYearOverYearComparison(
        currentDraft: DocumentContent,
        priorDraft: DocumentContent,
        service: LLMServiceProtocol
    ) async throws -> [ReviewFinding] {
        let systemPrompt = """
        You are a tax document comparison assistant. Compare the current year and prior year \
        tax returns to identify significant changes.

        IMPORTANT LANGUAGE RULES:
        - Use "Your return shows a change of..." not "There is a problem with..."
        - Use "You may want to verify" not "You need to explain"
        - Changes are not inherently good or bad — present them neutrally

        Flag changes where:
        - AGI changed by more than 20%
        - Any major income category changed by more than 25%
        - Deductions changed significantly
        - New income sources appeared or disappeared
        - Filing status changed
        - Effective tax rate changed by more than 2 percentage points

        Respond in JSON:
        {
            "findings": [
                {
                    "type": "yearOverYear",
                    "severity": "info" or "low" or "medium",
                    "description": "Neutral description of the change",
                    "draftValue": "Current year value",
                    "sourceValue": "Prior year value",
                    "recommendation": "Optional suggestion"
                }
            ]
        }
        """

        let userPrompt = """
        Current year draft (\(currentDraft.fileName)):
        \(String(currentDraft.extractedText.prefix(5000)))

        Prior year return (\(priorDraft.fileName)):
        \(String(priorDraft.extractedText.prefix(5000)))

        Compare these two tax returns and identify significant year-over-year changes.
        """

        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseFindingsResponse(response)
    }

    // MARK: - Response Parsing

    private func parseFindingsResponse(_ response: String) -> [ReviewFinding] {
        guard let jsonData = extractJSON(from: response) else {
            return [ReviewFinding(
                type: .verified,
                severity: .info,
                description: response
            )]
        }

        struct FindingsWrapper: Decodable {
            var findings: [FindingJSON]
        }

        struct FindingJSON: Decodable {
            var type: String
            var severity: String
            var description: String
            var draftLineReference: String?
            var draftValue: String?
            var sourceValue: String?
            var sourceDocument: String?
            var potentialSavings: String?
            var recommendation: String?
        }

        guard let wrapper = try? JSONDecoder().decode(FindingsWrapper.self, from: jsonData) else {
            return []
        }

        return wrapper.findings.map { f in
            ReviewFinding(
                type: FindingType(rawValue: f.type) ?? .verified,
                severity: FindingSeverity(rawValue: f.severity) ?? .info,
                description: f.description,
                draftLineReference: f.draftLineReference,
                draftValue: f.draftValue,
                sourceValue: f.sourceValue,
                sourceDocument: f.sourceDocument,
                potentialSavings: f.potentialSavings,
                recommendation: f.recommendation
            )
        }
    }

    private func extractJSON(from text: String) -> Data? {
        if let range = text.range(of: "```json") {
            let start = range.upperBound
            if let endRange = text.range(of: "```", range: start..<text.endIndex) {
                return String(text[start..<endRange.lowerBound]).data(using: .utf8)
            }
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end]).data(using: .utf8)
        }
        return nil
    }

    // MARK: - Scoring

    private func extractLineItems(from findings: [ReviewFinding]) -> [TaxLineItem] {
        findings.compactMap { finding -> TaxLineItem? in
            guard let lineRef = finding.draftLineReference else { return nil }
            return TaxLineItem(
                formName: lineRef.components(separatedBy: " Line").first ?? "Form 1040",
                lineNumber: lineRef,
                label: finding.description.prefix(60).description,
                reportedValue: finding.draftValue ?? "N/A",
                matchedSourceDoc: finding.sourceDocument,
                isVerified: finding.type == .verified
            )
        }
    }

    private func computeOverallScore(findings: [ReviewFinding]) -> Int {
        var score = 100
        for finding in findings {
            switch (finding.type, finding.severity) {
            case (.discrepancy, .critical): score -= 20
            case (.discrepancy, .high): score -= 15
            case (.discrepancy, .medium): score -= 10
            case (.discrepancy, .low): score -= 5
            case (.savingsOpportunity, .high): score -= 5
            case (.savingsOpportunity, .medium): score -= 3
            case (.auditRisk, .high): score -= 8
            case (.auditRisk, .medium): score -= 4
            default: break
            }
        }
        return max(0, min(100, score))
    }

    private func computeAuditRisk(findings: [ReviewFinding]) -> AuditRiskLevel {
        let maxSeverity = findings.map(\.severity).max() ?? .info
        let count = findings.count

        if maxSeverity >= .high || count >= 5 { return .high }
        if maxSeverity >= .medium || count >= 3 { return .elevated }
        if count >= 1 { return .moderate }
        return .low
    }
}
