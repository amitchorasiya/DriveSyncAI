// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - PII Types

enum PIIType: String, CaseIterable, Codable, Sendable {
    case ssn
    case creditCard
    case bankAccount
    case routingNumber
    case indianPAN
    case indianAadhaar
    case credential
    case dateOfBirth
    case phoneNumber
    case emailAddress

    var displayName: String {
        switch self {
        case .ssn: return "SSN"
        case .creditCard: return "Credit Card"
        case .bankAccount: return "Bank Account"
        case .routingNumber: return "Routing Number"
        case .indianPAN: return "PAN (India)"
        case .indianAadhaar: return "Aadhaar (India)"
        case .credential: return "Credential"
        case .dateOfBirth: return "Date of Birth"
        case .phoneNumber: return "Phone Number"
        case .emailAddress: return "Email Address"
        }
    }

    var redactionLabel: String {
        switch self {
        case .ssn: return "[SSN REDACTED]"
        case .creditCard: return "[CARD REDACTED]"
        case .bankAccount: return "[ACCOUNT REDACTED]"
        case .routingNumber: return "[ROUTING REDACTED]"
        case .indianPAN: return "[PAN REDACTED]"
        case .indianAadhaar: return "[AADHAAR REDACTED]"
        case .credential: return "[CREDENTIAL REDACTED]"
        case .dateOfBirth: return "[DOB REDACTED]"
        case .phoneNumber: return "[PHONE REDACTED]"
        case .emailAddress: return "[EMAIL REDACTED]"
        }
    }

    var severity: PIISeverity {
        switch self {
        case .ssn, .creditCard, .credential: return .critical
        case .bankAccount, .routingNumber, .indianAadhaar: return .high
        case .indianPAN, .dateOfBirth: return .medium
        case .phoneNumber, .emailAddress: return .low
        }
    }
}

enum PIISeverity: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: PIISeverity, rhs: PIISeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PIISensitivityLevel: String, CaseIterable, Sendable {
    case standard
    case maximum

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .maximum: return "Maximum"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Redacts SSNs, credit cards, bank accounts, PAN, Aadhaar, credentials"
        case .maximum: return "Also redacts phone numbers, email addresses, dates of birth"
        }
    }

    var minimumSeverity: PIISeverity {
        switch self {
        case .standard: return .medium
        case .maximum: return .low
        }
    }
}

// MARK: - Redaction Models

struct RedactedItem: Sendable {
    let type: PIIType
    let fileName: String
    let approximateLocation: String
}

struct RedactionSummary: Sendable {
    var totalRedactions: Int
    var redactionsByType: [PIIType: Int]
    var affectedDocuments: Set<String>
    var sensitivityLevel: PIISensitivityLevel

    init(sensitivityLevel: PIISensitivityLevel = .standard) {
        self.totalRedactions = 0
        self.redactionsByType = [:]
        self.affectedDocuments = []
        self.sensitivityLevel = sensitivityLevel
    }

    var isEmpty: Bool { totalRedactions == 0 }

    var formattedSummary: String {
        guard !isEmpty else { return "No sensitive items detected." }
        let types = redactionsByType
            .sorted { $0.value > $1.value }
            .map { "\($0.value) \($0.key.displayName)" }
            .joined(separator: ", ")
        return "\(totalRedactions) sensitive items redacted across \(affectedDocuments.count) document(s): \(types)"
    }

    var hasCriticalItems: Bool {
        redactionsByType.keys.contains { $0.severity == .critical }
    }
}

// MARK: - PII Engine

/// PII detection engine: built-in regex or optional Presidio (smart NER-based).
enum PIIEngine: String, CaseIterable, Codable, Sendable {
    case regex
    case presidio

    var displayName: String {
        switch self {
        case .regex: return "Regex (built-in)"
        case .presidio: return "Presidio (smart detect)"
        }
    }

    var description: String {
        switch self {
        case .regex: return "Pattern-based detection. No setup, works offline."
        case .presidio: return "Context-aware NER. Fewer false positives. Requires one-time setup."
        }
    }
}

// MARK: - PII Redactor Protocol

protocol PIIRedactorProtocol: Sendable {
    func redactText(_ text: String, fileName: String) async -> (redacted: String, items: [RedactedItem])
    func redactCorpus(documents: [DocumentContent]) async -> (redactedDocuments: [DocumentContent], summary: RedactionSummary)
    func detectPII(in text: String) async -> [PIIType]
}

/// Type-erased redactor so callers can use Regex or Presidio without storing actor types.
enum PIIRedactorRef: Sendable {
    case regex(PIIRedactionService)
    case presidio(PresidioPIIRedactor)

    func redactText(_ text: String, fileName: String) async -> (redacted: String, items: [RedactedItem]) {
        switch self {
        case .regex(let r): return await r.redactText(text, fileName: fileName)
        case .presidio(let p): return await p.redactText(text, fileName: fileName)
        }
    }

    func redactCorpus(documents: [DocumentContent]) async -> (redactedDocuments: [DocumentContent], summary: RedactionSummary) {
        switch self {
        case .regex(let r): return await r.redactCorpus(documents: documents)
        case .presidio(let p): return await p.redactCorpus(documents: documents)
        }
    }

    func detectPII(in text: String) async -> [PIIType] {
        switch self {
        case .regex(let r): return await r.detectPII(in: text)
        case .presidio(let p): return await p.detectPII(in: text)
        }
    }
}

/// Build the active redactor from app settings; falls back to regex if Presidio is selected but not set up.
func makePIIRedactor(
    engine: PIIEngine,
    sensitivity: PIISensitivityLevel
) -> PIIRedactorRef {
    switch engine {
    case .regex:
        return .regex(PIIRedactionService(sensitivity: sensitivity))
    case .presidio:
        if PresidioPaths.isPresidioAvailable {
            return .presidio(PresidioPIIRedactor(
                sensitivity: sensitivity,
                pythonURL: PresidioPaths.venvPythonURL,
                scriptURL: PresidioPaths.scriptURL
            ))
        }
        return .regex(PIIRedactionService(sensitivity: sensitivity))
    }
}

// MARK: - PIIRedactionService (Regex implementation)

actor PIIRedactionService: PIIRedactorProtocol {

    private let sensitivity: PIISensitivityLevel

    init(sensitivity: PIISensitivityLevel = .standard) {
        self.sensitivity = sensitivity
    }

    // MARK: - Public API (PIIRedactorProtocol)

    func redactText(_ text: String, fileName: String) async -> (redacted: String, items: [RedactedItem]) {
        var result = text
        var items: [RedactedItem] = []

        for piiType in PIIType.allCases {
            guard piiType.severity >= sensitivity.minimumSeverity else { continue }

            let patterns = regexPatterns(for: piiType)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                let nsRange = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, options: [], range: nsRange)

                for match in matches.reversed() {
                    guard let range = Range(match.range, in: result) else { continue }
                    let matched = String(result[range])

                    if shouldRedact(matched, type: piiType) {
                        let lineNumber = result[result.startIndex..<range.lowerBound]
                            .filter { $0 == "\n" }.count + 1
                        items.append(RedactedItem(
                            type: piiType,
                            fileName: fileName,
                            approximateLocation: "~line \(lineNumber)"
                        ))
                        result.replaceSubrange(range, with: piiType.redactionLabel)
                    }
                }
            }
        }

        return (result, items)
    }

    func redactCorpus(
        documents: [DocumentContent]
    ) async -> (redactedDocuments: [DocumentContent], summary: RedactionSummary) {
        var redacted: [DocumentContent] = []
        var summary = RedactionSummary(sensitivityLevel: sensitivity)

        for doc in documents {
            guard doc.isSuccessful else {
                redacted.append(doc)
                continue
            }

            let (redactedText, items) = await redactText(doc.extractedText, fileName: doc.fileName)

            if !items.isEmpty {
                summary.affectedDocuments.insert(doc.fileName)
                for item in items {
                    summary.totalRedactions += 1
                    summary.redactionsByType[item.type, default: 0] += 1
                }
            }

            var redactedDoc = doc
            redactedDoc.extractedText = redactedText
            redactedDoc.charCount = redactedText.count
            redacted.append(redactedDoc)
        }

        return (redacted, summary)
    }

    func detectPII(in text: String) async -> [PIIType] {
        var found: [PIIType] = []
        for piiType in PIIType.allCases {
            let patterns = regexPatterns(for: piiType)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let nsRange = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: nsRange) != nil {
                    found.append(piiType)
                    break
                }
            }
        }
        return found
    }

    // MARK: - Regex Patterns

    private func regexPatterns(for type: PIIType) -> [String] {
        switch type {
        case .ssn:
            return [
                #"\b\d{3}-\d{2}-\d{4}\b"#,
                #"\b\d{3}\s\d{2}\s\d{4}\b"#,
                #"(?:SSN|Social\s*Security)[:\s#]*\d{3}[- ]?\d{2}[- ]?\d{4}"#,
            ]
        case .creditCard:
            return [
                #"\b4\d{3}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"#,
                #"\b5[1-5]\d{2}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"#,
                #"\b3[47]\d{2}[- ]?\d{6}[- ]?\d{5}\b"#,
                #"\b6(?:011|5\d{2})[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"#,
            ]
        case .bankAccount:
            return [
                #"(?:account|acct)[:\s#]*\d{8,17}"#,
                #"(?:checking|savings|deposit)[:\s#]*\d{8,17}"#,
            ]
        case .routingNumber:
            return [
                #"(?:routing|ABA|transit)[:\s#]*\d{9}\b"#,
            ]
        case .indianPAN:
            return [
                #"\b[A-Z]{5}\d{4}[A-Z]\b"#,
            ]
        case .indianAadhaar:
            return [
                #"\b\d{4}\s\d{4}\s\d{4}\b"#,
                #"(?:Aadhaar|UID)[:\s#]*\d{4}\s?\d{4}\s?\d{4}"#,
            ]
        case .credential:
            return [
                #"(?:password|passwd|pwd|pin|secret|token)[:\s=]+\S+"#,
            ]
        case .dateOfBirth:
            return [
                #"(?:DOB|Date\s*of\s*Birth|Born|Birth\s*Date)[:\s]*\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#,
            ]
        case .phoneNumber:
            return [
                #"\b\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
                #"\+1[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
                #"\+91[-.\s]?\d{5}[-.\s]?\d{5}\b"#,
            ]
        case .emailAddress:
            return [
                #"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"#,
            ]
        }
    }

    // MARK: - Validation

    private func shouldRedact(_ value: String, type: PIIType) -> Bool {
        switch type {
        case .ssn:
            let digits = value.filter(\.isNumber)
            guard digits.count == 9 else { return false }
            let area = Int(digits.prefix(3)) ?? 0
            if area == 0 || area == 666 || area >= 900 { return false }
            let group = Int(digits.dropFirst(3).prefix(2)) ?? 0
            if group == 0 { return false }
            let serial = Int(digits.suffix(4)) ?? 0
            if serial == 0 { return false }
            return true

        case .creditCard:
            let digits = value.filter(\.isNumber)
            return luhnCheck(digits)

        case .indianPAN:
            let cleaned = value.trimmingCharacters(in: .whitespaces)
            guard cleaned.count == 10 else { return false }
            let fourthChar = cleaned[cleaned.index(cleaned.startIndex, offsetBy: 3)]
            return "ABCFGHLJPT".contains(fourthChar)

        case .indianAadhaar:
            let digits = value.filter(\.isNumber)
            guard digits.count == 12 else { return false }
            return digits.first != "0" && digits.first != "1"

        case .phoneNumber:
            let digits = value.filter(\.isNumber)
            return digits.count >= 10 && digits.count <= 15

        default:
            return true
        }
    }

    private func luhnCheck(_ number: String) -> Bool {
        guard number.count >= 13, number.count <= 19 else { return false }
        var sum = 0
        let digits = number.reversed().map { Int(String($0)) ?? 0 }
        for (index, digit) in digits.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
