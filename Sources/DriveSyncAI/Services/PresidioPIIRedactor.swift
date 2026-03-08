// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - Presidio entity type → PIIType

private func piiTypeFromPresidioEntity(_ entityType: String) -> PIIType? {
    switch entityType {
    case "US_SSN", "US_ITIN": return .ssn
    case "CREDIT_CARD": return .creditCard
    case "US_BANK_NUMBER", "IBAN_CODE": return .bankAccount
    case "IN_PAN": return .indianPAN
    case "IN_AADHAAR": return .indianAadhaar
    case "PHONE_NUMBER": return .phoneNumber
    case "EMAIL_ADDRESS": return .emailAddress
    case "PERSON": return .credential
    case "DATE_TIME": return .dateOfBirth
    default: return nil
    }
}

// MARK: - PresidioPIIRedactor

actor PresidioPIIRedactor: PIIRedactorProtocol {

    private let sensitivity: PIISensitivityLevel
    private let pythonURL: URL
    private let scriptURL: URL

    init(sensitivity: PIISensitivityLevel, pythonURL: URL, scriptURL: URL) {
        self.sensitivity = sensitivity
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
    }

    func redactText(_ text: String, fileName: String) async -> (redacted: String, items: [RedactedItem]) {
        let sensitivityStr = sensitivity == .maximum ? "maximum" : "standard"
        let input = ["text": text, "sensitivity": sensitivityStr, "mode": "redact"] as [String: Any]
        guard let inputData = try? JSONSerialization.data(withJSONObject: input),
              let inputStr = String(data: inputData, encoding: .utf8) else {
            return (text, [])
        }

        let (outputStr, exitCode) = await runScript(stdin: inputStr)
        guard exitCode == 0, let out = outputStr else { return (text, []) }

        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let redacted = json["redacted"] as? String,
              let entities = json["entities"] as? [[String: Any]] else {
            return (text, [])
        }

        let items: [RedactedItem] = entities.compactMap { entity in
            guard let typeStr = entity["type"] as? String,
                  let piiType = piiTypeFromPresidioEntity(typeStr),
                  piiType.severity >= sensitivity.minimumSeverity else { return nil }
            return RedactedItem(
                type: piiType,
                fileName: fileName,
                approximateLocation: "Presidio"
            )
        }
        return (redacted, items)
    }

    func redactCorpus(documents: [DocumentContent]) async -> (redactedDocuments: [DocumentContent], summary: RedactionSummary) {
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
        let sensitivityStr = sensitivity == .maximum ? "maximum" : "standard"
        let input = ["text": text, "sensitivity": sensitivityStr, "mode": "analyze"] as [String: Any]
        guard let inputData = try? JSONSerialization.data(withJSONObject: input),
              let inputStr = String(data: inputData, encoding: .utf8) else {
            return []
        }

        let (outputStr, exitCode) = await runScript(stdin: inputStr)
        guard exitCode == 0, let out = outputStr else { return [] }

        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [[String: Any]] else {
            return []
        }

        var found: Set<PIIType> = []
        for entity in entities {
            guard let typeStr = entity["type"] as? String,
                  let piiType = piiTypeFromPresidioEntity(typeStr),
                  piiType.severity >= sensitivity.minimumSeverity else { continue }
            found.insert(piiType)
        }
        return Array(found)
    }

    private func runScript(stdin: String) async -> (output: String?, exitCode: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path]

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { cont in
            do {
                try process.run()
                if let data = stdin.data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(data)
                }
                inPipe.fileHandleForWriting.closeFile()

                process.terminationHandler = { _ in
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: (output, process.terminationStatus))
                }
            } catch {
                cont.resume(returning: (nil, -1))
            }
        }
    }
}
