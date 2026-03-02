// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import ImageIO
import PDFKit

actor DriveAnalyzer {
    private let scheduler: AdaptiveScheduler

    init(scheduler: AdaptiveScheduler) {
        self.scheduler = scheduler
    }

    // MARK: - Tier 1: Deterministic Rules

    private static let clutterNames: Set<String> = [
        ".DS_Store", ".ds_store", "Thumbs.db", "thumbs.db", "desktop.ini",
        ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems",
        "__MACOSX", ".localized", ".com.apple.timemachine.donotpresent"
    ]

    private static let clutterExtensions: Set<String> = [
        "tmp", "temp", "bak", "swp", "swo", "cache", "log", "crash"
    ]

    private static let clutterPrefixes = ["~$", "._"]

    func analyzeTier1(root: URL, customRules: [CustomRule], scope: OrganizationScopePreference = .fullRecursive) async -> DriveAnalysis {
        var analysis = DriveAnalysis(rootPath: root)
        let fm = FileManager.default
        let startTime = Date()

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return analysis
        }

        var folderSet = Set<String>()
        var allFiles: [(url: URL, size: Int64, modified: Date?, isDir: Bool)] = []

        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isRegularFileKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let modified = resourceValues?.contentModificationDate

            let relativePath = url.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let depth = relativePath.isEmpty ? 0 : relativePath.components(separatedBy: "/").count

            if let maxDepth = scope.maxDepth, depth > maxDepth {
                if isDir {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDir {
                analysis.totalFolders += 1
                if depth <= 3 {
                    folderSet.insert(relativePath)
                }

                let isEmpty = (try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false
                if isEmpty {
                    analysis.clutterItems.append(ClutterItem(relativePath: relativePath, reason: .emptyFolder, size: 0))
                }
                continue
            }

            allFiles.append((url: url, size: size, modified: modified, isDir: false))
        }

        analysis.folderTree = folderSet.sorted()

        for file in allFiles {
            let url = file.url
            let size = file.size
            let modified = file.modified
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let relativePath = url.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parentFolder = url.deletingLastPathComponent().lastPathComponent

            analysis.totalFiles += 1
            analysis.totalSize += size

            if Self.clutterNames.contains(name) {
                analysis.clutterItems.append(ClutterItem(relativePath: relativePath, reason: .systemJunk, size: size))
                continue
            }
            if Self.clutterExtensions.contains(ext) {
                analysis.clutterItems.append(ClutterItem(relativePath: relativePath, reason: .tempFile, size: size))
                continue
            }
            if Self.clutterPrefixes.contains(where: { name.hasPrefix($0) }) {
                analysis.clutterItems.append(ClutterItem(relativePath: relativePath, reason: .systemJunk, size: size))
                continue
            }

            var hint = FileMetadataHint(
                relativePath: relativePath,
                fileName: name,
                size: size,
                modifiedDate: modified,
                parentFolder: parentFolder
            )

            let matchedRule = customRules.first { $0.matchesFile(name: name, size: size, modifiedDate: modified, parentFolder: parentFolder) }
            if matchedRule != nil {
                hint.confidence = 1.0
                if let cat = FileCategory.extensionMap[ext] {
                    hint.category = cat
                }
                analysis.categorizedFiles.append(hint)
                let cat = hint.category ?? .other
                var stats = analysis.categories[cat] ?? CategoryStats()
                stats.addFile(size: size, ext: ext, modified: modified)
                analysis.categories[cat] = stats
                continue
            }

            if let category = FileCategory.extensionMap[ext] {
                hint.category = category
                hint.confidence = 0.8
                analysis.categorizedFiles.append(hint)

                var stats = analysis.categories[category] ?? CategoryStats()
                stats.addFile(size: size, ext: ext, modified: modified)
                analysis.categories[category] = stats
            } else {
                hint.category = nil
                hint.confidence = 0
                analysis.ambiguousFiles.append(hint)

                var stats = analysis.categories[.other] ?? CategoryStats()
                stats.addFile(size: size, ext: ext, modified: modified)
                analysis.categories[.other] = stats
            }
        }

        analysis.mixedFolders = detectMixedFolders(analysis.categorizedFiles)
        analysis.scanDuration = Date().timeIntervalSince(startTime)
        return analysis
    }

    private func detectMixedFolders(_ files: [FileMetadataHint]) -> [MixedFolderInfo] {
        var folderContents: [String: (categories: [FileCategory: Int], files: Int, size: Int64)] = [:]

        for file in files {
            guard let cat = file.category else { continue }
            let parentPath = (file.relativePath as NSString).deletingLastPathComponent
            guard !parentPath.isEmpty else { continue }
            var entry = folderContents[parentPath] ?? (categories: [:], files: 0, size: 0)
            entry.categories[cat, default: 0] += 1
            entry.files += 1
            entry.size += file.size
            folderContents[parentPath] = entry
        }

        let mixedThreshold = 2
        return folderContents.compactMap { path, info in
            guard info.categories.count >= mixedThreshold, info.files >= 5 else { return nil }
            return MixedFolderInfo(
                folderName: (path as NSString).lastPathComponent,
                relativePath: path,
                totalFiles: info.files,
                categoryBreakdown: info.categories,
                totalSize: info.size
            )
        }.sorted { $0.totalFiles > $1.totalFiles }
    }

    // MARK: - Tier 2: Metadata Enrichment

    func enrichMetadata(analysis: inout DriveAnalysis) async {
        let root = analysis.rootPath

        for i in analysis.categorizedFiles.indices {
            let hint = analysis.categorizedFiles[i]
            let fullPath = root.appendingPathComponent(hint.relativePath)

            if hint.category == .photos || hint.category == .videos {
                if let exif = extractEXIF(from: fullPath) {
                    analysis.categorizedFiles[i].exifDate = exif.date
                    analysis.categorizedFiles[i].exifLocation = exif.location
                    if exif.date != nil || exif.location != nil {
                        analysis.categorizedFiles[i].confidence = max(hint.confidence, 0.9)
                    }
                }

                if analysis.categorizedFiles[i].exifDate == nil {
                    if let fnDate = dateFromFilename(hint.fileName) {
                        analysis.categorizedFiles[i].exifDate = fnDate
                        analysis.categorizedFiles[i].confidence = max(analysis.categorizedFiles[i].confidence, 0.75)
                    }
                }

                if analysis.categorizedFiles[i].exifDate == nil {
                    let (folderDate, eventName) = dateFromFolderName(hint.parentFolder)
                    if let fd = folderDate {
                        analysis.categorizedFiles[i].exifDate = fd
                        analysis.categorizedFiles[i].confidence = max(analysis.categorizedFiles[i].confidence, 0.65)
                    }
                    if let en = eventName {
                        analysis.categorizedFiles[i].eventName = en
                    }
                } else {
                    let (_, eventName) = dateFromFolderName(hint.parentFolder)
                    if let en = eventName {
                        analysis.categorizedFiles[i].eventName = en
                    }
                }

                if analysis.categorizedFiles[i].exifDate == nil, let mod = hint.modifiedDate {
                    analysis.categorizedFiles[i].exifDate = mod
                    analysis.categorizedFiles[i].confidence = max(analysis.categorizedFiles[i].confidence, 0.5)
                }
            }

            if hint.category == .installers {
                let ext = fullPath.pathExtension.lowercased()
                analysis.categorizedFiles[i].installerPlatform = InstallerPlatform.extensionMap[ext]
            }

            if hint.category == .documents {
                let ext = fullPath.pathExtension.lowercased()
                if ext == "pdf" {
                    if let pdfMeta = extractPDFMetadata(from: fullPath) {
                        analysis.categorizedFiles[i].pdfTitle = pdfMeta.title
                        analysis.categorizedFiles[i].pdfAuthor = pdfMeta.author
                        if pdfMeta.title != nil {
                            analysis.categorizedFiles[i].confidence = max(hint.confidence, 0.9)
                        }
                    }
                }
            }
        }

        for i in analysis.ambiguousFiles.indices {
            let hint = analysis.ambiguousFiles[i]
            let fullPath = root.appendingPathComponent(hint.relativePath)

            if let exif = extractEXIF(from: fullPath), (exif.date != nil || exif.location != nil) {
                analysis.ambiguousFiles[i].exifDate = exif.date
                analysis.ambiguousFiles[i].exifLocation = exif.location
                analysis.ambiguousFiles[i].category = .photos
                analysis.ambiguousFiles[i].confidence = 0.85
            }

            if fullPath.pathExtension.lowercased() == "pdf" {
                if let pdfMeta = extractPDFMetadata(from: fullPath) {
                    analysis.ambiguousFiles[i].pdfTitle = pdfMeta.title
                    analysis.ambiguousFiles[i].pdfAuthor = pdfMeta.author
                    analysis.ambiguousFiles[i].category = .documents
                    analysis.ambiguousFiles[i].confidence = 0.85
                }
            }

            let textExts: Set<String> = ["txt", "log", "csv", "tsv", "json", "xml", "yaml", "yml"]
            if textExts.contains(fullPath.pathExtension.lowercased()) {
                if let firstLine = readFirstLine(from: fullPath) {
                    analysis.ambiguousFiles[i].firstLineHint = String(firstLine.prefix(100))
                }
            }
        }

        let promoted = analysis.ambiguousFiles.filter { $0.confidence >= 0.7 }
        analysis.categorizedFiles.append(contentsOf: promoted)
        analysis.ambiguousFiles.removeAll { $0.confidence >= 0.7 }
    }

    // MARK: - Date Fallbacks

    private static let filenameDatePatterns: [(regex: NSRegularExpression, format: String)] = {
        let patterns: [(String, String)] = [
            (#"(\d{4})[\-_](\d{2})[\-_](\d{2})[\-_ ](\d{2})[\-_](\d{2})[\-_](\d{2})"#, "yyyy-MM-dd-HH-mm-ss"),
            (#"(\d{4})(\d{2})(\d{2})[\-_ ]?(\d{2})(\d{2})(\d{2})"#, "yyyyMMdd-HHmmss"),
            (#"(\d{4})[\-_](\d{2})[\-_](\d{2})"#, "yyyy-MM-dd"),
            (#"(\d{2})[\-_](\d{2})[\-_](\d{4})"#, "MM-dd-yyyy"),
        ]
        return patterns.compactMap { p in
            guard let regex = try? NSRegularExpression(pattern: p.0) else { return nil }
            return (regex, p.1)
        }
    }()

    private static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    func dateFromFilename(_ filename: String) -> Date? {
        let baseName = (filename as NSString).deletingPathExtension
        for (regex, format) in Self.filenameDatePatterns {
            let range = NSRange(baseName.startIndex..<baseName.endIndex, in: baseName)
            if let match = regex.firstMatch(in: baseName, range: range) {
                let matched = (baseName as NSString).substring(with: match.range)
                let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")

                let cleanFormat = format.components(separatedBy: CharacterSet.letters.inverted).joined()
                formatter.dateFormat = cleanFormat
                if let date = formatter.date(from: digits) {
                    let components = Calendar.current.dateComponents([.year], from: date)
                    if let year = components.year, year >= 1990, year <= 2030 {
                        return date
                    }
                }
            }
        }
        return nil
    }

    func dateFromFolderName(_ folderName: String) -> (date: Date?, eventName: String?) {
        let lower = folderName.lowercased()
        let components = folderName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

        var year: Int?
        var month: Int?
        var eventParts: [String] = []

        for comp in components {
            if let y = Int(comp), y >= 1990, y <= 2030 {
                year = y
            } else if let m = Self.monthNames[comp.lowercased()] {
                month = m
            } else if Int(comp) == nil {
                eventParts.append(comp)
            }
        }

        if year == nil {
            let yearRegex = try? NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = yearRegex?.firstMatch(in: lower, range: range) {
                let matched = (lower as NSString).substring(with: match.range)
                year = Int(matched)
            }
        }

        var date: Date?
        if let y = year {
            var dc = DateComponents()
            dc.year = y
            dc.month = month ?? 1
            dc.day = 1
            date = Calendar.current.date(from: dc)
        }

        let event = eventParts.isEmpty ? nil : eventParts.joined(separator: " ")
        return (date, event)
    }

    // MARK: - EXIF Extraction

    private struct EXIFData {
        var date: Date?
        var location: String?
    }

    private func extractEXIF(from url: URL) -> EXIFData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }

        var exif = EXIFData()

        if let exifDict = properties["{Exif}"] as? [String: Any],
           let dateString = exifDict["DateTimeOriginal"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            exif.date = formatter.date(from: dateString)
        }

        if let gps = properties["{GPS}"] as? [String: Any],
           let lat = gps["Latitude"] as? Double,
           let lon = gps["Longitude"] as? Double {
            let latRef = gps["LatitudeRef"] as? String ?? "N"
            let lonRef = gps["LongitudeRef"] as? String ?? "E"
            let signedLat = latRef == "S" ? -lat : lat
            let signedLon = lonRef == "W" ? -lon : lon
            exif.location = String(format: "%.4f, %.4f", signedLat, signedLon)
        }

        return exif
    }

    // MARK: - PDF Metadata

    private struct PDFMeta {
        var title: String?
        var author: String?
    }

    private func extractPDFMetadata(from url: URL) -> PDFMeta? {
        guard let doc = PDFDocument(url: url) else { return nil }
        guard let attrs = doc.documentAttributes else { return nil }

        var meta = PDFMeta()
        meta.title = attrs["Title"] as? String
        meta.author = attrs["Author"] as? String

        if let title = meta.title, title.trimmingCharacters(in: .whitespaces).isEmpty {
            meta.title = nil
        }

        return meta
    }

    // MARK: - Text First Line

    private func readFirstLine(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 256) else { return nil }
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        return text.components(separatedBy: .newlines).first
    }

    // MARK: - LLM Prompt Generation

    func generateLLMPrompt(analysis: DriveAnalysis) -> String {
        var parts: [String] = []

        parts.append("DRIVE ANALYSIS SUMMARY")
        parts.append("Total files: \(analysis.totalFiles), Total size: \(ByteCountFormatter.string(fromByteCount: analysis.totalSize, countStyle: .file))")
        parts.append("")

        parts.append("CATEGORIZED FILES:")
        for (cat, stats) in analysis.categories.sorted(by: { $0.value.fileCount > $1.value.fileCount }) {
            parts.append("  \(cat.displayName): \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))")
        }
        parts.append("")

        if !analysis.folderTree.isEmpty {
            parts.append("CURRENT FOLDER STRUCTURE (top 3 levels):")
            for folder in analysis.folderTree.prefix(50) {
                parts.append("  /\(folder)")
            }
            parts.append("")
        }

        if !analysis.ambiguousFiles.isEmpty {
            parts.append("UNCLASSIFIED FILES (\(analysis.ambiguousFiles.count) files):")
            for file in analysis.ambiguousFiles.prefix(100) {
                var desc = "  \(file.fileName) (\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)))"
                if let hint = file.firstLineHint {
                    desc += " hint: \"\(hint)\""
                }
                if let title = file.pdfTitle {
                    desc += " title: \"\(title)\""
                }
                desc += " in: \(file.parentFolder)"
                parts.append(desc)
            }
            parts.append("")
        }

        if !analysis.clutterItems.isEmpty {
            parts.append("DETECTED CLUTTER (\(analysis.clutterItems.count) items):")
            let grouped = Dictionary(grouping: analysis.clutterItems, by: \.reason)
            for (reason, items) in grouped {
                let totalSize = items.reduce(0) { $0 + $1.size }
                parts.append("  \(reason.displayName): \(items.count) items, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
            }
        }

        return parts.joined(separator: "\n")
    }

    static let systemPrompt = """
    You are a file organization assistant. Analyze the drive summary and suggest how to reorganize files for better structure.

    RULES:
    1. Suggest a clean folder hierarchy appropriate for the file types present.
    2. For unclassified files, classify them into categories and suggest destination folders.
    3. Suggest meaningful renames for files with unhelpful names (like IMG_2048.jpg, Document (3).pdf, Screenshot 2024-01-15.png). Use metadata hints if available.
    4. For clutter, recommend whether to delete or archive each category.
    5. Be conservative. When unsure, suggest "Other/" as the category.

    RESPOND WITH ONLY VALID JSON in this exact schema:
    {
      "folderStructure": [{"path": "string", "reason": "string"}],
      "moveRules": [{"pattern": "string", "from": "string or null", "to": "string", "reason": "string"}],
      "fileClassifications": [{"file": "string", "category": "string", "suggestedPath": "string or null", "confidence": 0.0-1.0}],
      "renameSuggestions": [{"from": "string", "to": "string", "reason": "string"}],
      "clutterActions": [{"path": "string", "action": "delete or archive", "reason": "string"}]
    }

    Keep suggestions practical and safe. Never suggest deleting important-looking files.
    """
}
