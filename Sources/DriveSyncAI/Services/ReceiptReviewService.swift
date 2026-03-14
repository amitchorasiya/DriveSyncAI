// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor ReceiptReviewService {
    
    private func piiRedactor() -> PIIRedactorRef {
        let engine = PIIEngine(rawValue: UserDefaults.standard.string(forKey: "piiEngine") ?? "") ?? .regex
        return makePIIRedactor(engine: engine, sensitivity: .standard)
    }
    
    func reviewReceipts(
        corpus: DocumentCorpus,
        configManager: LLMConfigManager
    ) async throws -> ReceiptReviewResult {
        let startTime = Date()
        let service = await configManager.currentService()
        let redactor = piiRedactor()
        
        // Redact corpus documents
        let (safeCorpusDocs, _) = await redactor.redactCorpus(
            documents: corpus.successfulDocuments
        )
        
        // Combine text from receipts
        let receiptText = safeCorpusDocs.prefix(10).map { doc in
            "[\(doc.fileName)]:\n\(doc.extractedText.prefix(2000))"
        }.joined(separator: "\n\n---\n\n")
        
        let systemPrompt = """
        You are a receipt and expense review assistant. Analyze the provided receipt documents to extract key details.
        
        PRIVACY NOTE: Sensitive personal information (SSNs, credit cards, etc.) has been redacted and replaced with placeholders like [SSN REDACTED] or [CARD REDACTED]. Do NOT attempt to guess these values.
        
        For each receipt, identify:
        - Merchant name
        - Date
        - Total amount
        - Category (e.g., Meals, Travel, Office Supplies, Software)
        - Any potential issues (missing details, blurry, duplicate)
        
        Respond in JSON format:
        {
            "items": [
                {
                    "merchant": "Merchant Name",
                    "date": "YYYY-MM-DD",
                    "amount": 123.45,
                    "category": "Category",
                    "status": "verified" (or "mismatch", "missing", "duplicate"),
                    "sourceDocument": "filename.pdf",
                    "notes": "Optional notes"
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
        Review these receipt documents:
        
        \(receiptText)
        
        Extract the details for each receipt and identify any anomalies.
        """
        
        let response = try await service.sendPrompt(system: systemPrompt, user: userPrompt)
        return parseResponse(response, startTime: startTime)
    }
    
    private func parseResponse(_ response: String, startTime: Date) -> ReceiptReviewResult {
        guard let jsonData = extractJSON(from: response),
              let wrapper = try? JSONDecoder().decode(ReceiptResponseWrapper.self, from: jsonData) else {
            return ReceiptReviewResult(
                items: [],
                totalAmount: 0,
                categoryBreakdown: [:],
                findings: [ReviewFinding(type: .discrepancy, severity: .medium, description: "Failed to parse receipt data")],
                reviewDuration: Date().timeIntervalSince(startTime)
            )
        }
        
        let items = wrapper.items.map { item in
            ReceiptItem(
                merchant: item.merchant,
                date: ISO8601DateFormatter().date(from: item.date ?? "") ?? Date(),
                amount: item.amount,
                category: item.category,
                status: ReceiptStatus(rawValue: item.status) ?? .verified,
                sourceDocument: item.sourceDocument,
                notes: item.notes
            )
        }
        
        let totalAmount = items.reduce(0) { $0 + ($1.amount ?? 0) }
        let categoryBreakdown = Dictionary(grouping: items, by: { $0.category ?? "Uncategorized" })
            .mapValues { $0.reduce(0) { $0 + ($1.amount ?? 0) } }
            
        let findings = wrapper.findings.map { f in
            ReviewFinding(
                type: FindingType(rawValue: f.type) ?? .verified,
                severity: FindingSeverity(rawValue: f.severity) ?? .info,
                description: f.description
            )
        }
        
        return ReceiptReviewResult(
            items: items,
            totalAmount: totalAmount,
            categoryBreakdown: categoryBreakdown,
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
    
    struct ReceiptResponseWrapper: Decodable {
        struct Item: Decodable {
            let merchant: String
            let date: String?
            let amount: Decimal?
            let category: String?
            let status: String
            let sourceDocument: String
            let notes: String?
        }
        struct Finding: Decodable {
            let type: String
            let severity: String
            let description: String
        }
        let items: [Item]
        let findings: [Finding]
    }
}
