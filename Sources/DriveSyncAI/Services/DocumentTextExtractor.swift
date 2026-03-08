// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import PDFKit
import Vision
import AppKit
import CoreXLSX

actor DocumentTextExtractor {

    private static let supportedTextExtensions: Set<String> = [
        "txt", "log", "md", "json", "xml", "yaml", "yml", "html", "htm",
        "css", "js", "ts", "swift", "py", "rb", "java", "c", "cpp", "h",
        "ini", "cfg", "conf", "env", "sh", "bat", "ps1", "rtf"
    ]

    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp"
    ]

    private static let minimumCharsPerPageForDigitalPDF = 50

    // MARK: - Public API

    func extractText(from url: URL, sourceFolder: URL) async -> DocumentContent {
        let ext = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        do {
            if ext == "pdf" {
                return try await extractPDF(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else if Self.supportedImageExtensions.contains(ext) {
                return try await extractImageOCR(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else if ext == "csv" {
                return try extractCSV(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else if ext == "docx" || ext == "doc" {
                return try await extractDOCX(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else if ext == "xlsx" {
                return try extractXLSX(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else if ext == "xls" {
                return extractUnsupported(url: url, fileSize: fileSize, sourceFolder: sourceFolder,
                                          note: "Legacy .xls format is not supported. Save as .xlsx (Excel 2007+) to analyze.")
            } else if Self.supportedTextExtensions.contains(ext) {
                return try extractPlainText(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            } else {
                return extractUnsupported(url: url, fileSize: fileSize, sourceFolder: sourceFolder)
            }
        } catch {
            return DocumentContent(
                fileName: url.lastPathComponent,
                filePath: url.path,
                fileSize: fileSize,
                fileType: ext,
                extractedText: "",
                extractionMethod: .failed,
                sourceFolder: sourceFolder,
                error: error.localizedDescription
            )
        }
    }

    func supportedExtensions() -> Set<String> {
        var exts = Self.supportedTextExtensions
        exts.formUnion(Self.supportedImageExtensions)
        exts.formUnion(["pdf", "csv", "docx", "doc", "xlsx", "xls"])
        return exts
    }

    // MARK: - PDF Extraction

    private func extractPDF(url: URL, fileSize: Int64, sourceFolder: URL) async throws -> DocumentContent {
        guard let pdfDoc = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpenFile("Unable to open PDF")
        }

        let pageCount = pdfDoc.pageCount
        var fullText = ""

        for i in 0..<pageCount {
            if let page = pdfDoc.page(at: i), let pageText = page.string {
                fullText += pageText
                if i < pageCount - 1 { fullText += "\n\n--- Page \(i + 2) ---\n\n" }
            }
        }

        let avgCharsPerPage = pageCount > 0 ? fullText.count / pageCount : 0
        let isScanned = pageCount > 0 && avgCharsPerPage < Self.minimumCharsPerPageForDigitalPDF

        if isScanned {
            let ocrText = try await ocrPDFPages(pdfDoc: pdfDoc)
            if ocrText.count > fullText.count {
                return DocumentContent(
                    fileName: url.lastPathComponent,
                    filePath: url.path,
                    fileSize: fileSize,
                    fileType: "pdf",
                    extractedText: ocrText,
                    pageCount: pageCount,
                    extractionMethod: .pdfOCR,
                    sourceFolder: sourceFolder
                )
            }
        }

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: "pdf",
            extractedText: fullText,
            pageCount: pageCount,
            extractionMethod: .pdfText,
            sourceFolder: sourceFolder
        )
    }

    private func ocrPDFPages(pdfDoc: PDFDocument) async throws -> String {
        var allText = ""
        let pageCount = pdfDoc.pageCount

        for i in 0..<pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)

            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext
            page.draw(with: .mediaBox, to: context)
            NSGraphicsContext.restoreGraphicsState()

            guard let cgImage = context.makeImage() else { continue }

            let pageText = try await performOCR(on: cgImage)
            if !pageText.isEmpty {
                allText += pageText
                if i < pageCount - 1 { allText += "\n\n--- Page \(i + 2) ---\n\n" }
            }
        }

        return allText
    }

    // MARK: - Image OCR

    private func extractImageOCR(url: URL, fileSize: Int64, sourceFolder: URL) async throws -> DocumentContent {
        guard let nsImage = NSImage(contentsOf: url),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            throw ExtractionError.cannotOpenFile("Unable to load image for OCR")
        }

        let text = try await performOCR(on: cgImage)

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: url.pathExtension.lowercased(),
            extractedText: text,
            extractionMethod: .visionOCR,
            ocrConfidence: text.isEmpty ? 0 : 0.8,
            sourceFolder: sourceFolder
        )
    }

    private func performOCR(on cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { observation -> String? in
                        guard observation.confidence >= 0.4 else { return nil }
                        return observation.topCandidates(1).first?.string
                    }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Plain Text

    private func extractPlainText(url: URL, fileSize: Int64, sourceFolder: URL) throws -> DocumentContent {
        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw ExtractionError.encodingError("Cannot decode text file")
        }

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: url.pathExtension.lowercased(),
            extractedText: text,
            extractionMethod: .directRead,
            sourceFolder: sourceFolder
        )
    }

    // MARK: - CSV

    private func extractCSV(url: URL, fileSize: Int64, sourceFolder: URL) throws -> DocumentContent {
        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw ExtractionError.encodingError("Cannot decode CSV file")
        }

        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var formatted = "CSV Data (\(lines.count) rows):\n\n"

        for (index, line) in lines.prefix(500).enumerated() {
            if index == 0 {
                formatted += "Header: \(line)\n"
                formatted += String(repeating: "-", count: 40) + "\n"
            } else {
                formatted += "Row \(index): \(line)\n"
            }
        }

        if lines.count > 500 {
            formatted += "\n... (\(lines.count - 500) additional rows truncated)\n"
        }

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: "csv",
            extractedText: formatted,
            extractionMethod: .directRead,
            sourceFolder: sourceFolder
        )
    }

    // MARK: - DOCX via textutil

    private func extractDOCX(url: URL, fileSize: Int64, sourceFolder: URL) async throws -> DocumentContent {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExtractionError.conversionFailed("textutil exited with code \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: url.pathExtension.lowercased(),
            extractedText: text,
            extractionMethod: .textutil,
            sourceFolder: sourceFolder
        )
    }

    // MARK: - XLSX via CoreXLSX

    private func extractXLSX(url: URL, fileSize: Int64, sourceFolder: URL) throws -> DocumentContent {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ExtractionError.cannotOpenFile("Unable to open XLSX file (corrupt or not a valid .xlsx)")
        }

        let sharedStrings = try? file.parseSharedStrings()
        let worksheetPaths = try file.parseWorksheetPaths()
        var sections: [String] = []
        var totalChars = 0
        let maxChars = 500_000

        for (sheetIndex, path) in worksheetPaths.enumerated() {
            guard totalChars < maxChars else { break }
            let worksheet = try file.parseWorksheet(at: path)
            var rowsText: [String] = []
            guard let rows = worksheet.data?.rows else { continue }

            for row in rows {
                var cellValues: [String] = []
                for cell in row.cells {
                    let value: String? = {
                        if let ss = sharedStrings, let s = cell.stringValue(ss) { return s }
                        if let v = cell.value { return v }
                        return cell.inlineString?.text
                    }()
                    cellValues.append(value ?? "")
                }
                let rowLine = cellValues.joined(separator: "\t")
                rowsText.append(rowLine)
                totalChars += rowLine.count + 1
                if totalChars >= maxChars { break }
            }

            let sheetTitle = "Sheet \(sheetIndex + 1)"
            let block = "--- \(sheetTitle) ---\n" + rowsText.joined(separator: "\n")
            sections.append(block)
        }

        var text = sections.joined(separator: "\n\n")
        if totalChars >= maxChars {
            text += "\n\n[Content truncated for very large workbook.]"
        }

        return DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: "xlsx",
            extractedText: text,
            extractionMethod: .coreXLSX,
            sourceFolder: sourceFolder
        )
    }

    // MARK: - Unsupported

    private func extractUnsupported(url: URL, fileSize: Int64, sourceFolder: URL, note: String? = nil) -> DocumentContent {
        DocumentContent(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            fileType: url.pathExtension.lowercased(),
            extractedText: "",
            extractionMethod: .unsupported,
            sourceFolder: sourceFolder,
            error: note ?? "File type '\(url.pathExtension)' is not supported for text extraction"
        )
    }
}

// MARK: - Errors

enum ExtractionError: LocalizedError {
    case cannotOpenFile(String)
    case encodingError(String)
    case conversionFailed(String)
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let msg): return msg
        case .encodingError(let msg): return msg
        case .conversionFailed(let msg): return msg
        case .ocrFailed(let msg): return msg
        }
    }
}
