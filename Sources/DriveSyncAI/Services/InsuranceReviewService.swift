// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor InsuranceReviewService {
    
    private func piiRedactor() -> PIIRedactorRef {
        let engine = PIIEngine(rawValue: UserDefaults.standard.string(forKey: "piiEngine") ?? "") ?? .regex
        return makePIIRedactor(engine: engine, sensitivity: .standard)
    }
    
    func reviewPolicy(
        corpus: DocumentCorpus,
        configManager: LLMConfigManager
    ) async throws -> InsuranceReviewResult {
        let startTime = Date()
        let service = await configManager.currentService()
        let redactor = piiRedactor()
        
        // Redact corpus documents
        let (safeCorpusDocs, _) = await redactor.redactCorpus(
            documents: corpus.successfulDocuments
        )
        
        // Combine text from policy documents
        let policyText = safeCorpusDocs.prefix(5).map { doc in
            "[\(doc.fileName)]:\n\(doc.extractedText.prefix(5000))"
        }.joined(separator: "\n\n---\n\n")
        
        let systemPrompt = """
        You are an insurance policy review assistant. Analyze the provided policy documents to extract key coverage details, exclusions, and gaps.
        
        PRIVACY NOTE: Sensitive personal information (SSNs, policy numbers, names, etc.) has been redacted and replaced with placeholders like [SSN REDACTED] or [NAME REDACTED]. Do NOT attempt to guess these values.
        
        Identify:
        - Policy Number
        - Provider
        - Effective Date
        - Expiration Date
        - Coverages (type, limit, deductible)
        - Exclusions (what is not covered)
        - Gaps (potential risks not covered)
        
        Respond in JSON format:
        {
            "policyNumber": "123456789",
            "provider": "Insurance Co",
            "effectiveDate": "YYYY-MM-DD",
            "expirationDate": "YYYY-MM-DD",
            "coverages": [
                {
                    "type": "Coverage Type",
                    "limit": "$1,000,000",
                    "deductible": "$500",
                    "notes": "Optional notes"
                }
            ],
            "exclusions": ["Exclusion 1", "Exclusion 2"],
            "gaps": ["Gap 1", "Gap 2"],
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
        Review these insurance policy documents:
        
        \(policyText)
        
        Extract the policy details and identify any coverage gaps.
        """
        
        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseResponse(response, startTime: startTime)
    }
    
    private func parseResponse(_ response: String, startTime: Date) -> InsuranceReviewResult {
        guard let jsonData = extractJSON(from: response),
              let wrapper = try? JSONDecoder().decode(InsuranceResponseWrapper.self, from: jsonData) else {
            return InsuranceReviewResult(
                policyNumber: nil,
                provider: nil,
                effectiveDate: nil,
                expirationDate: nil,
                coverages: [],
                exclusions: [],
                gaps: [],
                findings: [ReviewFinding(type: .discrepancy, severity: .medium, description: "Failed to parse insurance data")],
                reviewDuration: Date().timeIntervalSince(startTime)
            )
        }
        
        let coverages = wrapper.coverages.map { coverage in
            InsuranceCoverage(
                type: coverage.type,
                limit: coverage.limit,
                deductible: coverage.deductible,
                notes: coverage.notes
            )
        }
        
        let findings = wrapper.findings.map { f in
            ReviewFinding(
                type: FindingType(rawValue: f.type) ?? .verified,
                severity: FindingSeverity(rawValue: f.severity) ?? .info,
                description: f.description
            )
        }
        
        return InsuranceReviewResult(
            policyNumber: wrapper.policyNumber,
            provider: wrapper.provider,
            effectiveDate: wrapper.effectiveDate,
            expirationDate: wrapper.expirationDate,
            coverages: coverages,
            exclusions: wrapper.exclusions,
            gaps: wrapper.gaps,
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
    
    struct InsuranceResponseWrapper: Decodable {
        struct Coverage: Decodable {
            let type: String
            let limit: String
            let deductible: String?
            let notes: String?
        }
        struct Finding: Decodable {
            let type: String
            let severity: String
            let description: String
        }
        let policyNumber: String?
        let provider: String?
        let effectiveDate: String?
        let expirationDate: String?
        let coverages: [Coverage]
        let exclusions: [String]
        let gaps: [String]
        let findings: [Finding]
    }
}
