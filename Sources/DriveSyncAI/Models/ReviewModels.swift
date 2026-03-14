// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - Receipt Review Models

struct ReceiptItem: Identifiable, Codable, Sendable {
    let id: UUID
    var merchant: String
    var date: Date?
    var amount: Decimal?
    var category: String?
    var status: ReceiptStatus
    var sourceDocument: String
    var notes: String?
    
    init(
        merchant: String,
        date: Date? = nil,
        amount: Decimal? = nil,
        category: String? = nil,
        status: ReceiptStatus = .verified,
        sourceDocument: String,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.merchant = merchant
        self.date = date
        self.amount = amount
        self.category = category
        self.status = status
        self.sourceDocument = sourceDocument
        self.notes = notes
    }
}

enum ReceiptStatus: String, Codable, Sendable {
    case verified
    case mismatch
    case missing
    case duplicate
    case unknown
    
    var icon: String {
        switch self {
        case .verified: return "checkmark.circle.fill"
        case .mismatch: return "exclamationmark.triangle.fill"
        case .missing: return "questionmark.circle.fill"
        case .duplicate: return "doc.on.doc.fill"
        case .unknown: return "circle"
        }
    }
}

struct ReceiptReviewResult: Sendable {
    var items: [ReceiptItem]
    var totalAmount: Decimal
    var categoryBreakdown: [String: Decimal]
    var findings: [ReviewFinding]
    var reviewDuration: TimeInterval
}

// MARK: - Contract Review Models

struct ContractTerm: Identifiable, Codable, Sendable {
    let id: UUID
    var term: String
    var description: String
    var pageReference: String?
    var type: ContractTermType
    var severity: FindingSeverity
    
    init(
        term: String,
        description: String,
        pageReference: String? = nil,
        type: ContractTermType,
        severity: FindingSeverity = .info
    ) {
        self.id = UUID()
        self.term = term
        self.description = description
        self.pageReference = pageReference
        self.type = type
        self.severity = severity
    }
}

enum ContractTermType: String, Codable, Sendable {
    case obligation
    case right
    case date
    case risk
    case financial
    case general
    
    var displayName: String {
        rawValue.capitalized
    }
}

struct ContractReviewResult: Sendable {
    var summary: String
    var keyTerms: [ContractTerm]
    var criticalRisks: [ContractTerm]
    var importantDates: [ContractTerm]
    var findings: [ReviewFinding]
    var reviewDuration: TimeInterval
}

// MARK: - Insurance Review Models

struct InsuranceCoverage: Identifiable, Codable, Sendable {
    let id: UUID
    var type: String
    var limit: String
    var deductible: String?
    var notes: String?
    
    init(
        type: String,
        limit: String,
        deductible: String? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.limit = limit
        self.deductible = deductible
        self.notes = notes
    }
}

struct InsuranceReviewResult: Sendable {
    var policyNumber: String?
    var provider: String?
    var effectiveDate: String?
    var expirationDate: String?
    var coverages: [InsuranceCoverage]
    var exclusions: [String]
    var gaps: [String]
    var findings: [ReviewFinding]
    var reviewDuration: TimeInterval
}
