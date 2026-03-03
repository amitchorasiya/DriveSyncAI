// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import AppKit

/// Manages the lifecycle of the bundled llama-server background process.
/// Call `start()` on app launch when the provider is `.llamaCpp`.
/// Call `stop()` when the user switches away from the built-in provider.
@MainActor
final class LlamaCppServerManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = LlamaCppServerManager()

    // MARK: - Constants

    nonisolated static let port = 8181
    nonisolated static let baseURL = "http://127.0.0.1:\(port)/v1"
    nonisolated static let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!

    // MARK: - File Paths

    nonisolated static var drivesyncDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".drivesyncai", isDirectory: true)
    }

    nonisolated static var binaryURL: URL {
        drivesyncDir.appendingPathComponent("bin/llama-server")
    }

    nonisolated static var modelURL: URL {
        drivesyncDir
            .appendingPathComponent("models/qwen2.5-1.5b-instruct-q4_k_m.gguf")
    }

    // MARK: - Published State

    @Published var isRunning = false
    @Published var statusLine = "Not started"

    // MARK: - Private

    private var serverProcess: Process?

    private init() {}

    // MARK: - Lifecycle

    /// Starts llama-server if binary + model exist. Returns true if server becomes healthy.
    func start() async -> Bool {
        guard isReady else {
            statusLine = "Binary or model not found."
            return false
        }
        guard !isRunning else { return true }

        statusLine = "Starting built-in AI engine…"

        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = [
            "-m", Self.modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(Self.port)",
            "-c", "4096",
            "-ngl", "-1",        // GPU layers: -1 = all (Metal on Apple Silicon)
            "--log-disable"      // suppress verbose output
        ]
        // Ensure companion dylibs (libllama, libggml-metal, etc.) are found
        let binDirPath = Self.binaryURL.deletingLastPathComponent().path
        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = binDirPath
        process.environment = env
        // Suppress stdout/stderr so it doesn't pollute the app's console
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.statusLine = "Server stopped."
            }
        }

        do {
            try process.run()
        } catch {
            statusLine = "Failed to launch engine: \(error.localizedDescription)"
            return false
        }

        serverProcess = process

        // Poll health endpoint until ready (up to 30 seconds)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if await isHealthy() {
                isRunning = true
                statusLine = "Built-in AI engine running."
                return true
            }
        }

        process.terminate()
        serverProcess = nil
        statusLine = "Engine failed to start in time."
        return false
    }

    func stop() {
        serverProcess?.terminate()
        serverProcess = nil
        isRunning = false
        statusLine = "Stopped."
    }

    // MARK: - Health Check

    func isHealthy() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(Self.port)/health") else { return false }
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            let session = URLSession(configuration: config)
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Readiness Check

    nonisolated var isReady: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: Self.binaryURL.path)
            && fm.fileExists(atPath: Self.modelURL.path)
    }
}
