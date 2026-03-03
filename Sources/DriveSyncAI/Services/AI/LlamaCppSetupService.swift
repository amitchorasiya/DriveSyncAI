// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import AppKit

// MARK: - LlamaCppSetupService

/// Downloads the llama.cpp server binary and GGUF model, then starts the server.
/// No external installation required — everything is self-contained.
@MainActor
final class LlamaCppSetupService: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case fetchingRelease
        case downloadingBinary
        case downloadingModel
        case startingServer
        case done
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.fetchingRelease, .fetchingRelease),
                 (.downloadingBinary, .downloadingBinary), (.downloadingModel, .downloadingModel),
                 (.startingServer, .startingServer), (.done, .done): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Published State

    @Published var phase: Phase = .idle
    @Published var binaryProgress: Double = 0   // 0–1
    @Published var modelProgress: Double = 0     // 0–1
    @Published var statusLine: String = ""

    // MARK: - Model Constants

    static let modelFilename   = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    static let modelDownloadURL = URL(string:
        "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    )!
    /// Apache 2.0 licensed model — Qwen/Qwen2.5-1.5B-Instruct-GGUF on Hugging Face
    static let modelExpectedMinBytes: UInt64 = 900_000_000

    private static let binaryExpectedMinBytes: UInt64 = 4_000_000   // ~4 MB extracted

    // MARK: - Paths

    private var binDir: URL { LlamaCppServerManager.drivesyncDir.appendingPathComponent("bin") }
    private var modelsDir: URL { LlamaCppServerManager.drivesyncDir.appendingPathComponent("models") }
    private var binaryDest: URL { LlamaCppServerManager.binaryURL }
    private var modelDest: URL { LlamaCppServerManager.modelURL }

    // MARK: - Entry Point

    func run(configManager: LLMConfigManager) async {
        do {
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Could not create directories: \(error.localizedDescription)")
            return
        }

        // Step 1: ensure llama-server binary
        if !FileManager.default.isExecutableFile(atPath: binaryDest.path) {
            phase = .fetchingRelease
            statusLine = "Finding latest llama.cpp release…"
            do {
                let downloadURL = try await fetchBinaryDownloadURL()
                phase = .downloadingBinary
                statusLine = "Downloading AI engine…"
                binaryProgress = 0
                try await downloadAndExtractBinary(from: downloadURL)
            } catch {
                phase = .failed(classifyError(error))
                return
            }
        } else {
            binaryProgress = 1.0
        }

        // Step 2: ensure model file
        if !isModelValid() {
            phase = .downloadingModel
            statusLine = "Downloading AI model (~986 MB)…"
            modelProgress = 0
            do {
                try await downloadModel()
            } catch {
                phase = .failed(classifyError(error))
                return
            }
        } else {
            modelProgress = 1.0
        }

        // Step 3: start server
        phase = .startingServer
        statusLine = "Starting built-in AI engine…"
        let started = await LlamaCppServerManager.shared.start()
        if started {
            configManager.activeProvider = .llamaCpp
            configManager.activeModel = "qwen2.5:1.5b-instruct"
            configManager.isConfigured = true
            configManager.saveConfig()
            phase = .done
            statusLine = "AI ready."
        } else {
            phase = .failed("Engine failed to start. Please retry.")
        }
    }

    func retry(configManager: LLMConfigManager) async {
        binaryProgress = 0
        modelProgress = 0
        phase = .idle
        statusLine = ""
        await run(configManager: configManager)
    }

    // MARK: - GitHub Release Fetching

    private func fetchBinaryDownloadURL() async throws -> URL {
        // Try ggml-org first (current home), fall back to ggerganov
        let orgs = ["ggml-org", "ggerganov"]
        var lastError: Error = URLError(.badURL)

        for org in orgs {
            let apiURL = URL(string: "https://api.github.com/repos/\(org)/llama.cpp/releases/latest")!
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let assets = json["assets"] as? [[String: Any]] else { continue }

                // Find macOS ARM64 binary asset
                let candidates = assets.filter { asset in
                    guard let name = asset["name"] as? String else { return false }
                    let lower = name.lowercased()
                    return lower.contains("macos") && lower.contains("arm64") &&
                           (lower.hasSuffix(".zip") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz"))
                }

                if let asset = candidates.first,
                   let urlString = asset["browser_download_url"] as? String,
                   let url = URL(string: urlString) {
                    return url
                }
            } catch {
                lastError = error
            }
        }

        throw LlamaCppSetupError.binaryNotFound(lastError.localizedDescription)
    }

    // MARK: - Binary Download & Extraction

    private func downloadAndExtractBinary(from url: URL) async throws {
        let fm = FileManager.default
        let tmpArchive = binDir.appendingPathComponent("llama_archive_tmp")

        // Download archive
        try await downloadFile(from: url, to: tmpArchive, onProgress: { p in
            Task { @MainActor in self.binaryProgress = p * 0.8 }
        })

        // Extract
        statusLine = "Extracting AI engine…"
        let extractDir = binDir.appendingPathComponent("llama_extracted_tmp")
        try? fm.removeItem(at: extractDir)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let archivePath = tmpArchive.path
        let isZip = url.lastPathComponent.lowercased().hasSuffix(".zip")

        try await runProcess(
            executable: isZip ? "/usr/bin/unzip" : "/usr/bin/tar",
            arguments: isZip
                ? ["-o", archivePath, "-d", extractDir.path]
                : ["-xzf", archivePath, "-C", extractDir.path],
            errorMessage: "Failed to extract archive"
        )

        // Find the folder that contains llama-server and copy ALL its contents to binDir.
        // llama-server depends on companion dylibs (libllama, libggml-metal, etc.)
        // that must live in the same directory.
        guard let serverBin = findFile(named: "llama-server", in: extractDir) else {
            throw LlamaCppSetupError.binaryNotFound("llama-server not found in archive")
        }

        let sourceDir = serverBin.deletingLastPathComponent()

        // Copy every file from the archive's bin folder into our binDir
        let archiveContents = (try? fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)) ?? []
        for item in archiveContents {
            let dest = binDir.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: item, to: dest)
        }

        // Mark llama-server executable
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryDest.path)

        // Remove quarantine so macOS doesn't block execution
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.quarantine", binaryDest.path]
        try? xattr.run(); xattr.waitUntilExit()

        // Validate
        guard fm.isExecutableFile(atPath: binaryDest.path) else {
            throw LlamaCppSetupError.binaryNotFound("Extracted binary is not executable")
        }

        // Clean up
        try? fm.removeItem(at: tmpArchive)
        try? fm.removeItem(at: extractDir)

        binaryProgress = 1.0
        statusLine = "AI engine ready."
    }

    // MARK: - Model Download

    private func downloadModel() async throws {
        try await downloadFile(
            from: Self.modelDownloadURL,
            to: modelDest,
            onProgress: { p in
                Task { @MainActor in self.modelProgress = p }
            }
        )

        guard isModelValid() else {
            throw LlamaCppSetupError.downloadIncomplete("Model file is incomplete. Please retry.")
        }
        modelProgress = 1.0
    }

    // MARK: - Resumable Download (URLSessionDownloadDelegate for max throughput)

    /// Downloads `url` to `destination` with resumption support and progress callbacks.
    /// Uses URLSessionDownloadTask + delegate — Foundation handles all I/O, no per-byte Swift overhead.
    private func downloadFile(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fm = FileManager.default
        let partialURL = destination.appendingPathExtension("partial")

        var startByte: UInt64 = 0
        if fm.fileExists(atPath: partialURL.path),
           let attrs = try? fm.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? UInt64, size > 0 {
            startByte = size
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 600   // 10 min — large model downloads can be slow
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if startByte > 0 {
            request.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = DownloadDelegate(
                destination: partialURL,
                startByte: startByte,
                onProgress: onProgress,
                onDone: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 3600    // 1 hour max
            config.httpMaximumConnectionsPerHost = 4
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            delegate.task = task
            task.resume()
        }

        // Move partial → final
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partialURL, to: destination)
        onProgress(1.0)
    }
}

// MARK: - DownloadDelegate

/// URLSessionDataDelegate that streams response data directly to disk with no per-byte Swift overhead.
private final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let startByte: UInt64
    private let onProgress: (Double) -> Void
    private let onDone: (Error?) -> Void

    private var fileHandle: FileHandle?
    private var totalBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private let lock = NSLock()

    weak var task: URLSessionDataTask?

    init(destination: URL, startByte: UInt64, onProgress: @escaping (Double) -> Void, onDone: @escaping (Error?) -> Void) {
        self.destination = destination
        self.startByte = startByte
        self.onProgress = onProgress
        self.onDone = onDone
        self.receivedBytes = startByte
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completionHandler(.cancel)
            onDone(LlamaCppSetupError.downloadFailed("HTTP \(code)"))
            return
        }

        let contentLength = UInt64(max(0, response.expectedContentLength))
        lock.lock()
        totalBytes = contentLength + startByte
        lock.unlock()

        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            fm.createFile(atPath: destination.path, contents: nil)
        }
        if let fh = try? FileHandle(forWritingTo: destination) {
            if startByte > 0 { fh.seekToEndOfFile() }
            lock.lock()
            fileHandle = fh
            lock.unlock()
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
            onDone(LlamaCppSetupError.downloadFailed("Cannot open file for writing"))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        fileHandle?.write(data)
        receivedBytes += UInt64(data.count)
        let progress = totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
        lock.unlock()
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        try? fileHandle?.close()
        fileHandle = nil
        lock.unlock()
        onDone(error)
        session.invalidateAndCancel()
    }
}

// MARK: - Validation & Helpers (extension keeps main class body cleaner)

extension LlamaCppSetupService {

    func isModelValid() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelDest.path),
              let size = attrs[.size] as? UInt64 else { return false }
        return size >= Self.modelExpectedMinBytes
    }

    func runProcess(executable: String, arguments: [String], errorMessage: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: LlamaCppSetupError.extractionFailed("\(errorMessage): \(msg)"))
                }
            }
            do { try process.run() } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func findFile(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    func classifyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("no space") || msg.contains("disk full") {
            return "Not enough disk space. You need at least 1.2 GB free."
        }
        if msg.contains("network") || msg.contains("timeout") || msg.contains("connection") {
            return "Download interrupted. Check your internet connection and retry."
        }
        if let setupErr = error as? LlamaCppSetupError {
            return setupErr.userMessage
        }
        return error.localizedDescription
    }
}

// MARK: - Errors

enum LlamaCppSetupError: LocalizedError {
    case binaryNotFound(String)
    case downloadFailed(String)
    case downloadIncomplete(String)
    case extractionFailed(String)

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .binaryNotFound(let d): return "Could not find llama.cpp engine binary. \(d)"
        case .downloadFailed(let d): return "Download failed: \(d)"
        case .downloadIncomplete(let d): return d
        case .extractionFailed(let d): return "Extraction failed: \(d)"
        }
    }
}
