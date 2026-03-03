// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import AppKit

// MARK: - Thread-safe box for use in closure captures

private final class ThreadSafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - OllamaSetupService

/// Manages automatic Ollama CLI detection, model integrity validation, model pull with
/// streaming progress, auto-retry on interruption, and admin-password escalation.
@MainActor
final class OllamaSetupService: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case checkingOllama
        case validatingModel
        case pullingModel
        case needsAdminPassword
        case retrying(attempt: Int)
        case done
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checkingOllama, .checkingOllama),
                 (.validatingModel, .validatingModel), (.pullingModel, .pullingModel),
                 (.needsAdminPassword, .needsAdminPassword), (.done, .done):
                return true
            case (.retrying(let a), .retrying(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Published State

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var retryCount: Int = 0
    @Published var ollamaInstalled: Bool = false

    // MARK: - Constants

    static let targetModel = "qwen2.5:1.5b-instruct"
    static let maxRetries = 3
    nonisolated static let expectedMinBytes: UInt64 = 900_000_000   // ~900 MB for a valid pull
    private static let retryDelayNS: UInt64 = 3_000_000_000     // 3 seconds

    private static let ollamaPaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/usr/bin/ollama",
    ]

    // MARK: - Entry Point

    func run(configManager: LLMConfigManager) async {
        phase = .checkingOllama
        statusLine = "Checking Ollama installation…"
        retryCount = 0

        guard let ollamaPath = findOllamaPath() else {
            phase = .failed("ollamaNotFound")
            statusLine = "Ollama not installed."
            return
        }
        ollamaInstalled = true

        phase = .validatingModel
        statusLine = "Checking model status…"

        if await isModelValid(ollamaPath: ollamaPath) {
            finalize(configManager: configManager)
            return
        }

        await pullWithRetry(ollamaPath: ollamaPath, configManager: configManager, attempt: 1)
    }

    func retryWithAdminPassword(_ password: String, configManager: LLMConfigManager) async {
        guard let ollamaPath = findOllamaPath() else {
            phase = .failed("Ollama not found. Please install Ollama first.")
            return
        }
        phase = .pullingModel
        statusLine = "Pulling model with admin access…"
        progress = 0

        do {
            try await pullModelWithSudo(ollamaPath: ollamaPath, password: password)
            phase = .validatingModel
            statusLine = "Validating model…"
            if await isModelValid(ollamaPath: ollamaPath) {
                finalize(configManager: configManager)
            } else {
                phase = .failed("Model download appears incomplete. Please retry.")
            }
        } catch {
            phase = .failed(Self.classifyError(error.localizedDescription, exitCode: 1))
        }
    }

    func retry(configManager: LLMConfigManager) async {
        retryCount = 0
        progress = 0
        await run(configManager: configManager)
    }

    // MARK: - Pull with Auto-Retry

    private func pullWithRetry(ollamaPath: String, configManager: LLMConfigManager, attempt: Int) async {
        if attempt > 1 {
            phase = .retrying(attempt: attempt - 1)
            statusLine = "Retrying… (\(attempt - 1)/\(Self.maxRetries))"
            try? await Task.sleep(nanoseconds: Self.retryDelayNS)
        }

        phase = .pullingModel
        statusLine = attempt == 1 ? "Downloading model…" : "Downloading model (attempt \(attempt))…"
        retryCount = attempt - 1

        let result = await runPull(ollamaPath: ollamaPath)

        switch result {
        case .success:
            phase = .validatingModel
            statusLine = "Validating download…"
            if await isModelValid(ollamaPath: ollamaPath) {
                finalize(configManager: configManager)
            } else if attempt <= Self.maxRetries {
                await pullWithRetry(ollamaPath: ollamaPath, configManager: configManager, attempt: attempt + 1)
            } else {
                phase = .failed("Model download appears incomplete after \(Self.maxRetries) attempts. Please try again.")
            }

        case .permissionDenied:
            phase = .needsAdminPassword
            statusLine = "Admin permission required."

        case .failure(let msg) where attempt < Self.maxRetries:
            await pullWithRetry(ollamaPath: ollamaPath, configManager: configManager, attempt: attempt + 1)
            _ = msg

        case .failure(let msg):
            phase = .failed(msg)
        }
    }

    // MARK: - Pull Execution (streams stdout for progress)

    private enum PullResult: Sendable {
        case success
        case permissionDenied
        case failure(String)
    }

    private func runPull(ollamaPath: String) async -> PullResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["pull", Self.targetModel]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stderrBox = ThreadSafeBox<Data>(Data())
            let lastProgressBox = ThreadSafeBox<Double>(0.0)

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrBox.value.append(handle.availableData)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.components(separatedBy: "\n") where !line.isEmpty {
                    if let parsed = Self.parseProgressLine(line) {
                        let current = lastProgressBox.value
                        if parsed > current {
                            lastProgressBox.value = parsed
                            Task { @MainActor [weak self] in
                                self?.progress = parsed
                                self?.statusLine = "Downloading… \(Int(parsed * 100))%"
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let exitCode = proc.terminationStatus
                let stderr = String(data: stderrBox.value, encoding: .utf8) ?? ""

                if exitCode == 0 {
                    continuation.resume(returning: .success)
                } else if stderr.lowercased().contains("permission denied") ||
                          stderr.lowercased().contains("operation not permitted") {
                    continuation.resume(returning: .permissionDenied)
                } else {
                    let msg = Self.classifyError(stderr, exitCode: exitCode)
                    continuation.resume(returning: .failure(msg))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure("Could not launch Ollama: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Pull with sudo via osascript

    private func pullModelWithSudo(ollamaPath: String, password: String) async throws {
        let escapedPassword = password.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
        let shellCmd = "\(ollamaPath) pull \(Self.targetModel)"
        let script = "do shell script \"\(shellCmd)\" with administrator privileges password \"\(escapedPassword)\""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: NSError(
                        domain: "OllamaSetup",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Model Validation

    private func isModelValid(ollamaPath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["list"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let isValid = Self.checkModelInList(output)
                continuation.resume(returning: isValid)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Static Helpers (nonisolated so they can be called from background closures)

    nonisolated static func checkModelInList(_ output: String) -> Bool {
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            guard lower.contains("qwen2.5") && (lower.contains("1.5b") || lower.contains("1.5")) else { continue }
            let sizeBytes = parseSizeFromLine(line)
            return sizeBytes >= expectedMinBytes
        }
        return false
    }

    nonisolated static func parseSizeFromLine(_ line: String) -> UInt64 {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for (i, part) in parts.enumerated() {
            if let value = Double(part), i + 1 < parts.count {
                let unit = parts[i + 1].uppercased()
                switch unit {
                case "GB": return UInt64(value * 1_000_000_000)
                case "MB": return UInt64(value * 1_000_000)
                case "KB": return UInt64(value * 1_000)
                default: break
                }
            }
        }
        return 0
    }

    nonisolated static func parseProgressLine(_ line: String) -> Double? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let completed = json["completed"] as? Double,
           let total = json["total"] as? Double,
           total > 0 {
            return min(completed / total, 1.0)
        }
        return nil
    }

    nonisolated static func classifyError(_ stderr: String, exitCode: Int32) -> String {
        let lower = stderr.lowercased()
        if lower.contains("no space left") || lower.contains("disk full") || lower.contains("not enough space") {
            return "Not enough disk space. You need at least 1.2 GB free."
        }
        if lower.contains("connection refused") || lower.contains("connection reset") ||
           lower.contains("timeout") || lower.contains("eof") || lower.contains("network") {
            return "Download interrupted. Check your internet connection and try again."
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return "Admin permission required to complete setup."
        }
        if lower.contains("not found") || lower.contains("no such file") {
            return "Ollama installation seems incomplete. Please reinstall Ollama."
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Setup failed (exit code \(exitCode)). Please retry."
        }
        return trimmed.count > 140 ? String(trimmed.prefix(140)) + "…" : trimmed
    }

    // MARK: - Ollama Path Detection

    private func findOllamaPath() -> String? {
        for path in Self.ollamaPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return runWhich("ollama")
    }

    private func runWhich(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    // MARK: - Finalize

    private func finalize(configManager: LLMConfigManager) {
        configManager.activeProvider = .ollama
        configManager.activeModel = Self.targetModel
        configManager.isConfigured = true
        configManager.saveConfig()
        progress = 1.0
        statusLine = "AI setup complete."
        phase = .done
    }
}
