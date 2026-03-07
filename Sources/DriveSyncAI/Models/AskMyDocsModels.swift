// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - Document Domain Classification

enum DocumentDomain: String, CaseIterable, Codable, Identifiable {
    case financial
    case legal
    case medical
    case technical
    case academic
    case mixed
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .financial: return "Financial / Tax"
        case .legal: return "Legal"
        case .medical: return "Medical"
        case .technical: return "Technical"
        case .academic: return "Academic"
        case .mixed: return "Mixed"
        case .general: return "General"
        }
    }

    var icon: String {
        switch self {
        case .financial: return "dollarsign.circle"
        case .legal: return "building.columns"
        case .medical: return "cross.case"
        case .technical: return "wrench.and.screwdriver"
        case .academic: return "graduationcap"
        case .mixed: return "square.grid.3x3"
        case .general: return "doc.text"
        }
    }
}

// MARK: - Extraction Method

enum ExtractionMethod: String, Codable, Sendable {
    case pdfText
    case pdfOCR
    case visionOCR
    case directRead
    case textutil
    case coreXLSX
    case unsupported
    case failed

    var displayName: String {
        switch self {
        case .pdfText: return "PDF Text"
        case .pdfOCR: return "PDF OCR"
        case .visionOCR: return "Image OCR"
        case .directRead: return "Text"
        case .textutil: return "DOCX"
        case .coreXLSX: return "Excel"
        case .unsupported: return "Unsupported"
        case .failed: return "Failed"
        }
    }

    var isOCR: Bool {
        self == .pdfOCR || self == .visionOCR
    }
}

// MARK: - Document Content

struct DocumentContent: Identifiable, Sendable {
    let id: UUID
    var fileName: String
    var filePath: String
    var fileSize: Int64
    var fileType: String
    var extractedText: String
    var pageCount: Int?
    var charCount: Int
    var extractionMethod: ExtractionMethod
    var ocrConfidence: Double?
    var sourceFolder: URL
    var error: String?

    init(
        fileName: String,
        filePath: String,
        fileSize: Int64,
        fileType: String,
        extractedText: String,
        pageCount: Int? = nil,
        extractionMethod: ExtractionMethod,
        ocrConfidence: Double? = nil,
        sourceFolder: URL,
        error: String? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.fileSize = fileSize
        self.fileType = fileType
        self.extractedText = extractedText
        self.pageCount = pageCount
        self.charCount = extractedText.count
        self.extractionMethod = extractionMethod
        self.ocrConfidence = ocrConfidence
        self.sourceFolder = sourceFolder
        self.error = error
    }

    var isSuccessful: Bool {
        extractionMethod != .failed && extractionMethod != .unsupported && error == nil
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedCharCount: String {
        if charCount >= 1000 {
            return String(format: "%.1fK", Double(charCount) / 1000.0)
        }
        return "\(charCount)"
    }
}

// MARK: - Document Source

enum ScanStatus: String, Sendable {
    case pending
    case scanning
    case completed
    case failed
}

struct DocumentSource: Identifiable, Sendable {
    let id: UUID
    var url: URL
    var displayName: String
    var documentCount: Int
    var totalChars: Int
    var scanStatus: ScanStatus
    var errorMessage: String?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.displayName = url.lastPathComponent
        self.documentCount = 0
        self.totalChars = 0
        self.scanStatus = .pending
    }
}

// MARK: - Document Corpus

struct DocumentCorpus: Sendable {
    var sources: [DocumentSource]
    var documents: [DocumentContent]
    var totalChars: Int
    var detectedDomain: DocumentDomain
    var domainConfidence: Double
    var scanDuration: TimeInterval
    var supportedFileCount: Int
    var unsupportedFileCount: Int
    var ocrDocCount: Int

    init() {
        self.sources = []
        self.documents = []
        self.totalChars = 0
        self.detectedDomain = .general
        self.domainConfidence = 0
        self.scanDuration = 0
        self.supportedFileCount = 0
        self.unsupportedFileCount = 0
        self.ocrDocCount = 0
    }

    var successfulDocuments: [DocumentContent] {
        documents.filter(\.isSuccessful)
    }

    var estimatedTokens: Int {
        totalChars / 4
    }

    var isLargeCorpus: Bool {
        totalChars > 50_000
    }
}

// MARK: - Extracted Data Point

struct ExtractedDataPoint: Identifiable, Codable, Sendable {
    let id: UUID
    var label: String
    var value: String
    var category: String?
    var sourceDocument: String
    var pageReference: String?
    var confidence: Double

    init(
        label: String,
        value: String,
        category: String? = nil,
        sourceDocument: String,
        pageReference: String? = nil,
        confidence: Double = 0.8
    ) {
        self.id = UUID()
        self.label = label
        self.value = value
        self.category = category
        self.sourceDocument = sourceDocument
        self.pageReference = pageReference
        self.confidence = confidence
    }
}

// MARK: - Insight Result

struct InsightResult: Sendable {
    var answer: String
    var dataPoints: [ExtractedDataPoint]
    var supportingDocuments: [String]
    var suggestedFollowUps: [String]
    var completenessNote: String?

    init(
        answer: String,
        dataPoints: [ExtractedDataPoint] = [],
        supportingDocuments: [String] = [],
        suggestedFollowUps: [String] = [],
        completenessNote: String? = nil
    ) {
        self.answer = answer
        self.dataPoints = dataPoints
        self.supportingDocuments = supportingDocuments
        self.suggestedFollowUps = suggestedFollowUps
        self.completenessNote = completenessNote
    }
}

// MARK: - Model Recommendation

struct ModelRecommendation: Sendable {
    var currentModel: String
    var currentProvider: String
    var recommendedModel: String
    var recommendedProvider: String
    var reason: String
    var isInstalled: Bool
    var pullCommand: String?
    var confidenceScore: Double
    var alternatives: [(model: String, reason: String)]

    var needsPull: Bool {
        !isInstalled && pullCommand != nil
    }
}

// MARK: - Report Generation

enum ReportFormat: String, CaseIterable, Identifiable {
    case pdf
    case csv
    case markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: return "PDF Report"
        case .csv: return "CSV / Excel"
        case .markdown: return "Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .markdown: return "md"
        }
    }

    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .markdown: return "doc.plaintext"
        }
    }
}

struct GeneratedReport: Identifiable, Sendable {
    let id: UUID
    var title: String
    var format: ReportFormat
    var generatedAt: Date
    var fileURL: URL?
    var query: String
    var dataPointCount: Int

    init(title: String, format: ReportFormat, query: String, dataPointCount: Int, fileURL: URL? = nil) {
        self.id = UUID()
        self.title = title
        self.format = format
        self.generatedAt = Date()
        self.fileURL = fileURL
        self.query = query
        self.dataPointCount = dataPointCount
    }
}

// MARK: - Tax Review Models (US / IRS)

enum FindingType: String, Codable, Sendable {
    case discrepancy
    case savingsOpportunity
    case auditRisk
    case yearOverYear
    case verified
}

enum FindingSeverity: String, Codable, Sendable, Comparable {
    case info
    case low
    case medium
    case high
    case critical

    private var sortOrder: Int {
        switch self {
        case .info: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self {
        case .info: return "Info"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .low: return "exclamationmark.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

struct ReviewFinding: Identifiable, Codable, Sendable {
    let id: UUID
    var type: FindingType
    var severity: FindingSeverity
    var description: String
    var draftLineReference: String?
    var draftValue: String?
    var sourceValue: String?
    var sourceDocument: String?
    var potentialSavings: String?
    var recommendation: String?

    init(
        type: FindingType,
        severity: FindingSeverity,
        description: String,
        draftLineReference: String? = nil,
        draftValue: String? = nil,
        sourceValue: String? = nil,
        sourceDocument: String? = nil,
        potentialSavings: String? = nil,
        recommendation: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.severity = severity
        self.description = description
        self.draftLineReference = draftLineReference
        self.draftValue = draftValue
        self.sourceValue = sourceValue
        self.sourceDocument = sourceDocument
        self.potentialSavings = potentialSavings
        self.recommendation = recommendation
    }
}

struct TaxLineItem: Identifiable, Codable, Sendable {
    let id: UUID
    var formName: String
    var lineNumber: String
    var label: String
    var reportedValue: String
    var matchedSourceDoc: String?
    var isVerified: Bool

    init(
        formName: String,
        lineNumber: String,
        label: String,
        reportedValue: String,
        matchedSourceDoc: String? = nil,
        isVerified: Bool = false
    ) {
        self.id = UUID()
        self.formName = formName
        self.lineNumber = lineNumber
        self.label = label
        self.reportedValue = reportedValue
        self.matchedSourceDoc = matchedSourceDoc
        self.isVerified = isVerified
    }
}

enum AuditRiskLevel: String, Codable, Sendable {
    case low
    case moderate
    case elevated
    case high

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .low: return "shield.checkmark"
        case .moderate: return "shield.lefthalf.filled"
        case .elevated: return "exclamationmark.shield"
        case .high: return "exclamationmark.shield.fill"
        }
    }
}

struct TaxReviewResult: Sendable {
    var overallScore: Int
    var auditRiskLevel: AuditRiskLevel
    var draftDocument: String
    var lineItems: [TaxLineItem]
    var findings: [ReviewFinding]
    var reviewDuration: TimeInterval

    var accuracyFindings: [ReviewFinding] {
        findings.filter { $0.type == .verified || $0.type == .discrepancy }
    }

    var savingsFindings: [ReviewFinding] {
        findings.filter { $0.type == .savingsOpportunity }
    }

    var auditRiskFindings: [ReviewFinding] {
        findings.filter { $0.type == .auditRisk }
    }

    var yoyFindings: [ReviewFinding] {
        findings.filter { $0.type == .yearOverYear }
    }

    var discrepancyCount: Int {
        findings.filter { $0.type == .discrepancy }.count
    }

    var verifiedCount: Int {
        findings.filter { $0.type == .verified }.count
    }

    var totalPotentialSavings: String? {
        let amounts = savingsFindings.compactMap { finding -> Double? in
            guard let savings = finding.potentialSavings else { return nil }
            let digits = savings.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Double(digits)
        }
        guard !amounts.isEmpty else { return nil }
        let total = amounts.reduce(0, +)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: total))
    }

    static let fullDisclaimer = """
        IMPORTANT NOTICE: This tool performs automated document comparison and \
        pattern analysis for informational and educational purposes only. It does \
        NOT constitute tax advice, tax preparation, tax planning, or filing services. \
        The analysis provided may contain errors, omissions, or inaccuracies. Tax laws \
        are complex and change frequently. Always consult a qualified tax professional \
        — such as a Certified Public Accountant (CPA), Enrolled Agent (EA), or Tax \
        Attorney — before making any tax-related decisions or filing any tax return. \
        The developer assumes no liability for any financial decisions made based on \
        this analysis. Use at your own risk.
        """

    static let shortDisclaimer =
        "Informational analysis only — not tax advice. Verify all findings with a qualified tax professional before filing."
}

// MARK: - IRS Form Mappings

enum IRSFormMapping {
    struct FormLine {
        let formCode: String
        let formName: String
        let draftLines: [String]
        let keywords: [String]
    }

    static let mappings: [FormLine] = [
        FormLine(formCode: "W-2", formName: "Wages and Salary",
                 draftLines: ["1040 Line 1a"], keywords: ["wages", "salary", "tips", "compensation"]),
        FormLine(formCode: "1099-INT", formName: "Interest Income",
                 draftLines: ["1040 Line 2b", "Schedule B"], keywords: ["interest", "savings", "CD"]),
        FormLine(formCode: "1099-DIV", formName: "Dividend Income",
                 draftLines: ["1040 Line 3a", "1040 Line 3b", "Schedule B"], keywords: ["dividend", "qualified"]),
        FormLine(formCode: "1099-NEC", formName: "Self-Employment Income",
                 draftLines: ["Schedule C Line 1"], keywords: ["nonemployee", "freelance", "contractor"]),
        FormLine(formCode: "1099-MISC", formName: "Miscellaneous Income",
                 draftLines: ["Schedule C", "1040 Line 8"], keywords: ["royalties", "rents", "other income"]),
        FormLine(formCode: "1099-B", formName: "Capital Gains / Losses",
                 draftLines: ["Schedule D", "Form 8949"], keywords: ["proceeds", "cost basis", "capital gain", "stock"]),
        FormLine(formCode: "1098", formName: "Mortgage Interest",
                 draftLines: ["Schedule A Line 8a"], keywords: ["mortgage", "interest paid", "points"]),
        FormLine(formCode: "1098-E", formName: "Student Loan Interest",
                 draftLines: ["1040 Line 21"], keywords: ["student loan", "interest"]),
        FormLine(formCode: "1098-T", formName: "Tuition Statement",
                 draftLines: ["Form 8863"], keywords: ["tuition", "education", "scholarship"]),
        FormLine(formCode: "5498-SA", formName: "HSA Contributions",
                 draftLines: ["1040 Line 13"], keywords: ["HSA", "health savings"]),
        FormLine(formCode: "5498", formName: "IRA Contributions",
                 draftLines: ["1040 Line 20"], keywords: ["IRA", "traditional IRA", "Roth"]),
        FormLine(formCode: "1095-A", formName: "Health Insurance Marketplace",
                 draftLines: ["1040 Line 17", "Form 8962"], keywords: ["marketplace", "premium tax credit"]),
        FormLine(formCode: "1099-R", formName: "Retirement Distributions",
                 draftLines: ["1040 Line 4a", "1040 Line 4b"], keywords: ["distribution", "pension", "annuity", "401k"]),
        FormLine(formCode: "1099-G", formName: "Government Payments",
                 draftLines: ["1040 Line 7"], keywords: ["unemployment", "tax refund", "state refund"]),
        FormLine(formCode: "1099-SA", formName: "HSA Distributions",
                 draftLines: ["Form 8889"], keywords: ["HSA distribution", "medical expense"]),
        FormLine(formCode: "SSA-1099", formName: "Social Security Benefits",
                 draftLines: ["1040 Line 6a", "1040 Line 6b"], keywords: ["social security", "SSA"]),
    ]

    static func formLine(for code: String) -> FormLine? {
        mappings.first { $0.formCode.lowercased() == code.lowercased() }
    }
}
