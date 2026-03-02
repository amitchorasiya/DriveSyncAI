// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct ExiftoolResult: Sendable {
    let filePath: String
    let dateOriginal: Date?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let make: String?
    let model: String?
}

actor ExiftoolService {
    private let exiftoolPath: String?

    init() {
        let candidates = ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool", "/usr/bin/exiftool"]
        self.exiftoolPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    var isAvailable: Bool {
        exiftoolPath != nil
    }

    func extractBatch(directory: URL) async throws -> [ExiftoolResult] {
        guard let tool = exiftoolPath else {
            throw ExiftoolError.notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = [
            "-json", "-r",
            "-DateTimeOriginal", "-GPSLatitude", "-GPSLongitude",
            "-Make", "-Model",
            "-d", "%Y-%m-%dT%H:%M:%S",
            directory.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExiftoolError.processFailure(Int(process.terminationStatus))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }

        return try parseJSON(data, baseDirectory: directory)
    }

    func extractSingle(file: URL) async throws -> ExiftoolResult? {
        guard let tool = exiftoolPath else {
            throw ExiftoolError.notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = [
            "-json",
            "-DateTimeOriginal", "-GPSLatitude", "-GPSLongitude",
            "-Make", "-Model",
            "-d", "%Y-%m-%dT%H:%M:%S",
            file.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExiftoolError.processFailure(Int(process.terminationStatus))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }

        let results = try parseJSON(data, baseDirectory: file.deletingLastPathComponent())
        return results.first
    }

    private func parseJSON(_ data: Data, baseDirectory: URL) throws -> [ExiftoolResult] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ExiftoolError.invalidJSON
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        var results: [ExiftoolResult] = []

        for entry in jsonArray {
            guard let sourcePath = entry["SourceFile"] as? String else { continue }

            var dateOriginal: Date?
            if let dateStr = entry["DateTimeOriginal"] as? String {
                dateOriginal = dateFormatter.date(from: dateStr)
                if dateOriginal == nil {
                    let fallback = DateFormatter()
                    fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    fallback.locale = Locale(identifier: "en_US_POSIX")
                    dateOriginal = fallback.date(from: dateStr)
                }
            }

            let lat = entry["GPSLatitude"] as? Double
            let lon = entry["GPSLongitude"] as? Double
            let make = entry["Make"] as? String
            let model = entry["Model"] as? String

            results.append(ExiftoolResult(
                filePath: sourcePath,
                dateOriginal: dateOriginal,
                gpsLatitude: lat,
                gpsLongitude: lon,
                make: make,
                model: model
            ))
        }

        return results
    }
}

enum ExiftoolError: LocalizedError {
    case notInstalled
    case processFailure(Int)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "exiftool is not installed. Install via 'brew install exiftool'."
        case .processFailure(let code):
            return "exiftool exited with code \(code)"
        case .invalidJSON:
            return "Failed to parse exiftool JSON output"
        }
    }
}
