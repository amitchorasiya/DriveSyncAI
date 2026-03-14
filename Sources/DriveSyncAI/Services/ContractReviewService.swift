// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor ContractReviewService {
    
    private func piiRedactor() -> PIIRedactorRef {
        let engine = PIIEngine(rawValue: UserDefaults.standard.string(forKey: "piiEngine") ?? "") ?? .regex
        return makePIIRedactor(engine: engine, sensitivity: .standard)
    }
    
    func reviewContract(
        corpus: DocumentCorpus,
        configManager: LLMConfigManager
    ) async throws -> ContractReviewResult {
        let startTime = Date()
        let service = await configManager.currentService()
        let redactor = piiRedactor()
        
        // Redact corpus documents
        let (safeCorpusDocs, _) = await redactor.redactCorpus(
            documents: corpus.successfulDocuments
        )
        
        // Combine text from contract documents
        let contractText = safeCorpusDocs.prefix(5).map { doc in
            "[\(doc.fileName)]:\n\(doc.extractedText.prefix(5000))"
        }.joined(separator: "\n\n---\n\n")
        
        let systemPrompt = """
        You are a legal contract review assistant. Analyze the provided contract documents to extract key terms, obligations, rights, and risks.
        
        PRIVACY NOTE: Sensitive personal information (SSNs, names, etc.) has been redacted and replaced with placeholders like [SSN REDACTED] or [NAME REDACTED]. Do NOT attempt to guess these values.
        
        Identify:
        - Key terms (definitions, scope, payment, termination)
        - Obligations (what each party must do)
        - Rights (what each party can do)
        - Important dates (deadlines, renewal, expiration)
        - Risks (indemnification, liability, warranties)
        
        Respond in JSON format:
        {
            "summary": "Brief summary of the contract",
            "keyTerms": [
                {
                    "term": "Term Name",
                    "description": "Description of the term",
                    "pageReference": "Page 1",
                    "type": "obligation" (or "right", "date", "risk", "financial", "general"),
                    "severity": "info" (or "low", "medium", "high", "critical")
                }
            ],
            "findings": [
                {
                    "type": "discrepancy" or "verified",
                    "severity": "info" or "low" or "medium",
                    "description": "Description of finding"
                }
            ]
        }
        """
        
        let userPrompt = """
        Review these contract documents:
        
        \(contractText)
        
        Extract the key terms and identify any risks or unusual clauses.
        """
        
        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseResponse(response, startTime: startTime)
    }
    
    private func parseResponse(_ response: String, startTime: Date) -> ContractReviewResult {
        guard let jsonData = extractJSON(from: response),
              let wrapper = try? JSONDecoder().decode(ContractResponseWrapper.self, from: jsonData) else {
            return ContractReviewResult(
                summary: "Failed to parse contract data",
                keyTerms: [],
                criticalRisks: [],
                importantDates: [],
                findings: [ReviewFinding(type: .discrepancy, severity: .medium, description: "Failed to parse contract data")],
                reviewDuration: Date().timeIntervalSince(startTime)
            )
        }
        
        let allTerms = wrapper.keyTerms.map { term in
            ContractTerm(
                term: term.term,
                description: term.description,
                pageReference: term.pageReference,
                type: ContractTermType(rawValue: term.type) ?? .general,
                severity: FindingSeverity(rawValue: term.severity) ?? .info
            )
        }
        
        let criticalRisks = allTerms.filter { $0.type == .risk && ($0.severity == .high || $0.severity == .critical) }
        let importantDates = allTerms.filter { $0.type == .date }
        
        let findings = wrapper.findings.map { f in
            ReviewFinding(
                type: FindingType(rawValue: f.type) ?? .verified,
                severity: FindingSeverity(rawValue: f.severity) ?? .info,
                description: f.description
            )
        }
        
        return ContractReviewResult(
            summary: wrapper.summary,
            keyTerms: allTerms,
            criticalRisks: criticalRisks,
            importantDates: importantDates,
            findings: findings,
            reviewDuration: Date().timeIntervalSince(startTime)
        )
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
    
    struct ContractResponseWrapper: Decodable {
        struct Term: Decodable {
            let term: String
            let description: String
            let pageReference: String?
            let type: String
            let severity: String
        }
        struct Finding: Decodable {
            let type: String
            let severity: String
            let description: String
        }
        let summary: String
        let keyTerms: [Term]
        let findings: [Finding]
    }
}
