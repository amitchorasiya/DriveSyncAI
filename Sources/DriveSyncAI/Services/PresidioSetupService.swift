// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import AppKit

// MARK: - Presidio Paths (nonisolated for use from any context)

enum PresidioPaths {
    static let presidioSubdir = "presidio"
    static let venvBinPython = "bin/python3"
    static let scriptName = "presidio_redact.py"

    static var presidioDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".drivesyncai", isDirectory: true)
            .appendingPathComponent(presidioSubdir, isDirectory: true)
    }

    static var venvPythonURL: URL {
        presidioDir.appendingPathComponent(venvBinPython, isDirectory: false)
    }

    static var scriptURL: URL {
        presidioDir.appendingPathComponent(scriptName, isDirectory: false)
    }

    static var isPresidioAvailable: Bool {
        let fm = FileManager.default
        let python = venvPythonURL
        let script = scriptURL
        return fm.fileExists(atPath: python.path) && fm.isExecutableFile(atPath: python.path)
            && fm.fileExists(atPath: script.path)
    }
}

// MARK: - Presidio Setup

/// One-time setup of Presidio (Python venv + presidio-analyzer, presidio-anonymizer) for optional PII smart-detect.
@MainActor
final class PresidioSetupService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checkingPython
        case creatingVenv
        case installingPresidio
        case downloadingSpacy
        case writingScript
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var statusLine: String = ""

    /// Directory under ~/.drivesyncai/presidio for venv and script.
    static var presidioDir: URL { PresidioPaths.presidioDir }

    /// Path to the venv's python3 after setup.
    static var venvPythonURL: URL { PresidioPaths.venvPythonURL }

    /// Path to the redaction script after setup.
    static var scriptURL: URL { PresidioPaths.scriptURL }

    /// Returns true if Presidio is already set up (venv exists and script exists).
    static var isPresidioAvailable: Bool { PresidioPaths.isPresidioAvailable }

    /// Returns path to python3 on PATH, or nil if not found.
    static func findPython3() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["python3", "-c", "import sys; print(sys.executable)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet.newlines)
        } catch {
            return nil
        }
    }

    /// Run full setup: create dir, venv, pip install, write script.
    func runSetup() async {
        phase = .checkingPython
        statusLine = "Checking for Python 3…"

        guard let systemPython = Self.findPython3() else {
            phase = .failed("Python 3 not found. Install Python 3 from python.org or Homebrew (brew install python).")
            return
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.presidioDir, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Could not create directory: \(error.localizedDescription)")
            return
        }

        phase = .creatingVenv
        statusLine = "Creating virtual environment…"
        let venvResult = await runCommand(
            executable: systemPython,
            arguments: ["-m", "venv", Self.presidioDir.path],
            currentDirectory: nil
        )
        guard venvResult == 0 else {
            phase = .failed("Failed to create virtual environment (exit \(venvResult)).")
            return
        }

        let pip = Self.presidioDir
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pip3", isDirectory: false)
        guard fm.fileExists(atPath: pip.path) else {
            phase = .failed("pip not found in venv.")
            return
        }

        phase = .installingPresidio
        statusLine = "Installing Presidio (analyzer + anonymizer)…"
        let installResult = await runCommand(
            executable: pip.path,
            arguments: ["install", "--quiet", "presidio-analyzer", "presidio-anonymizer"],
            currentDirectory: Self.presidioDir.path
        )
        guard installResult == 0 else {
            phase = .failed("Failed to install Presidio. Check your network or try: \(pip.path) install presidio-analyzer presidio-anonymizer")
            return
        }

        phase = .downloadingSpacy
        statusLine = "Downloading language model (small)…"
        let pythonPath = Self.venvPythonURL.path
        let spacyResult = await runCommand(
            executable: pythonPath,
            arguments: ["-m", "spacy", "download", "en_core_web_sm"],
            currentDirectory: Self.presidioDir.path
        )
        if spacyResult != 0 {
            statusLine = "Spacy model optional; continuing without it."
        }

        phase = .writingScript
        statusLine = "Writing redaction script…"
        do {
            try Self.presidioRedactScriptContent.write(to: Self.scriptURL, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Could not write script: \(error.localizedDescription)")
            return
        }

        phase = .done
        statusLine = "Presidio is ready. You can use “Presidio (smart detect)” in PII settings."
    }

    private func runCommand(executable: String, arguments: [String], currentDirectory: String?) async -> Int32 {
        await withCheckedContinuation { cont in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            if let dir = currentDirectory {
                task.currentDirectoryURL = URL(fileURLWithPath: dir)
            }
            task.terminationHandler = { _ in
                cont.resume(returning: task.terminationStatus)
            }
            do {
                try task.run()
            } catch {
                cont.resume(returning: -1)
            }
        }
    }

    private static let presidioRedactScriptContent = """
#!/usr/bin/env python3
# Presidio PII analyze + anonymize; reads JSON from stdin, writes JSON to stdout.
# Input: one JSON line {"text": "...", "sensitivity": "standard"|"maximum", "mode": "redact"|"analyze"}
#   mode "analyze": output only {"entities": [{"type": "US_SSN", ...}, ...]}
#   mode "redact" (default): output {"redacted": "...", "entities": [...]}
# Output: one JSON line.

import json
import sys

def main():
    try:
        line = sys.stdin.readline()
        if not line:
            sys.exit(1)
        req = json.loads(line)
        text = req.get("text", "")
        sensitivity = req.get("sensitivity", "standard")
        mode = req.get("mode", "redact")
    except (json.JSONDecodeError, KeyError) as e:
        print(json.dumps({"error": str(e)}), flush=True)
        sys.exit(1)

    try:
        from presidio_analyzer import AnalyzerEngine
        from presidio_anonymizer import AnonymizerEngine
        from presidio_anonymizer.entities import OperatorConfig
    except ImportError as e:
        print(json.dumps({"error": "Presidio not installed: " + str(e)}), flush=True)
        sys.exit(1)

    LABELS = {
        "US_SSN": "[SSN REDACTED]",
        "US_ITIN": "[SSN REDACTED]",
        "CREDIT_CARD": "[CARD REDACTED]",
        "US_BANK_NUMBER": "[ACCOUNT REDACTED]",
        "IBAN_CODE": "[ACCOUNT REDACTED]",
        "IN_PAN": "[PAN REDACTED]",
        "IN_AADHAAR": "[AADHAAR REDACTED]",
        "PHONE_NUMBER": "[PHONE REDACTED]",
        "EMAIL_ADDRESS": "[EMAIL REDACTED]",
        "PERSON": "[NAME REDACTED]",
        "DATE_TIME": "[DOB REDACTED]",
    }

    analyzer = AnalyzerEngine()
    results = analyzer.analyze(text=text, language="en")

    if sensitivity == "standard":
        allowed = {"US_SSN", "US_ITIN", "CREDIT_CARD", "US_BANK_NUMBER", "IBAN_CODE", "IN_PAN", "IN_AADHAAR"}
        results = [r for r in results if r.entity_type in allowed]

    entities_out = [{"type": r.entity_type, "start": r.start, "end": r.end} for r in results]

    if mode == "analyze":
        print(json.dumps({"entities": entities_out}), flush=True)
        return

    anonymizer = AnonymizerEngine()
    operators = {}
    for r in results:
        if r.entity_type not in operators:
            operators[r.entity_type] = OperatorConfig("replace", {"new_value": LABELS.get(r.entity_type, "[REDACTED]")})

    try:
        redacted = anonymizer.anonymize(text=text, analyzer_results=results, operators=operators)
        out = {"redacted": redacted.text, "entities": entities_out}
    except Exception as e:
        print(json.dumps({"error": str(e)}), flush=True)
        sys.exit(1)

    print(json.dumps(out), flush=True)

if __name__ == "__main__":
    main()
"""
}
