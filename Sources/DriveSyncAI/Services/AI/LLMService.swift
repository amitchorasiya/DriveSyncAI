// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import os.log

// MARK: - Protocol

protocol LLMServiceProtocol: Sendable {
    func sendPrompt(system: String, user: String) async throws -> String
    func validateConnection() async -> Bool
    func availableModels() async throws -> [String]
}

enum LLMError: LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case apiError(Int, String)
    case invalidJSON(String)
    case modelNotFound(String)
    case rateLimited
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
        case .modelNotFound(let model): return "Model not found: \(model)"
        case .rateLimited: return "Rate limited. Please wait and try again."
        case .timeout: return "Request timed out."
        }
    }
}

// MARK: - Response Validator

struct LLMResponseValidator {
    static func extractJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return trimmed
        }

        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            let json = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return json
        }

        if let openBrace = trimmed.firstIndex(of: "{"),
           let closeBrace = trimmed.lastIndex(of: "}") {
            let candidate = String(trimmed[openBrace...closeBrace])
            if let data = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return candidate
            }
        }

        return nil
    }

    static func parseOrganizeResponse(from text: String) throws -> AIOrganizeResponse {
        guard let jsonString = extractJSON(from: text) else {
            throw LLMError.invalidJSON("Could not extract valid JSON from response")
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.invalidJSON("Failed to encode JSON string")
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AIOrganizeResponse.self, from: data)
        } catch {
            throw LLMError.invalidJSON("JSON decode failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Ollama

final class OllamaLLMService: LLMServiceProtocol, @unchecked Sendable {
    let baseURL: String
    let model: String
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.2") {
        self.baseURL = baseURL
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "stream": false,
            "options": ["temperature": 0.3]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse("Missing message.content in Ollama response")
        }
        return content
    }

    func validateConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        let url = URL(string: "\(baseURL)/api/tags")!
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }
    }
}

// MARK: - OpenAI

final class OpenAILLMService: LLMServiceProtocol, @unchecked Sendable {
    let apiKey: String
    let model: String
    let baseURL: String
    private let session: URLSession

    init(apiKey: String, model: String = "gpt-4o-mini", baseURL: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Not an HTTP response")
        }
        if http.statusCode == 429 { throw LLMError.rateLimited }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse("Missing choices[0].message.content")
        }
        return content
    }

    func validateConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        let url = URL(string: "\(baseURL)/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }.sorted()
    }
}

// MARK: - Anthropic

final class AnthropicLLMService: LLMServiceProtocol, @unchecked Sendable {
    let apiKey: String
    let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Not an HTTP response")
        }
        if http.statusCode == 429 { throw LLMError.rateLimited }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw LLMError.invalidResponse("Missing content[0].text in Anthropic response")
        }
        return text
    }

    func validateConnection() async -> Bool {
        do {
            _ = try await sendPrompt(system: "Reply with: ok", user: "ping")
            return true
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        return LLMProviderType.anthropic.knownModels
    }
}

// MARK: - Google Gemini

final class GoogleLLMService: LLMServiceProtocol, @unchecked Sendable {
    let apiKey: String
    let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "gemini-2.0-flash") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [
                ["parts": [["text": user]]]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Not an HTTP response")
        }
        if http.statusCode == 429 { throw LLMError.rateLimited }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw LLMError.invalidResponse("Missing candidates[0].content.parts[0].text in Gemini response")
        }
        return text
    }

    func validateConnection() async -> Bool {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
    }
}

// MARK: - Perplexity (OpenAI-compatible)

final class PerplexityLLMService: LLMServiceProtocol, @unchecked Sendable {
    let apiKey: String
    let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "sonar") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.perplexity.ai/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Not an HTTP response")
        }
        if http.statusCode == 429 { throw LLMError.rateLimited }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse("Missing choices[0].message.content")
        }
        return content
    }

    func validateConnection() async -> Bool {
        do {
            _ = try await sendPrompt(system: "Reply with: ok", user: "ping")
            return true
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        return LLMProviderType.perplexity.knownModels
    }
}

// MARK: - llama.cpp (OpenAI-compatible local server)

/// Connects to the bundled llama-server running on localhost:8181.
/// Uses the OpenAI-compatible /v1/chat/completions endpoint.
final class LlamaCppLLMService: LLMServiceProtocol, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.amitchorasiya.drivesyncai", category: "LlamaCppLLM")

    private let baseURL: String
    private let model: String
    private let session: URLSession

    init(baseURL: String = "http://127.0.0.1:8181/v1", model: String = "qwen2.5:1.5b-instruct") {
        self.baseURL = baseURL
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    func sendPrompt(system: String, user: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log.error("Built-in engine request failed: \(String(describing: error.localizedDescription))")
            throw LLMError.connectionFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            Self.log.error("Built-in engine returned non-HTTP response")
            throw LLMError.connectionFailed("No HTTP response from local AI engine")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.log.error("Built-in engine HTTP \(http.statusCode): \(String(describing: msg.prefix(200)))")
            throw LLMError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("Built-in engine invalid response shape: \(String(describing: raw.prefix(300)))")
            throw LLMError.invalidResponse("Missing choices[0].message.content from local engine")
        }
        return content
    }

    func validateConnection() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8181/health") else { return false }
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            let s = URLSession(configuration: config)
            let (_, response) = try await s.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        return LLMProviderType.llamaCpp.knownModels
    }
}

// MARK: - Factory

enum LLMServiceFactory {
    static func create(config: LLMProviderConfig, apiKey: String?) -> LLMServiceProtocol {
        switch config.provider {
        case .llamaCpp:
            return LlamaCppLLMService(baseURL: config.effectiveBaseURL, model: config.model)
        case .ollama:
            return OllamaLLMService(baseURL: config.effectiveBaseURL, model: config.model)
        case .openai:
            return OpenAILLMService(apiKey: apiKey ?? "", model: config.model, baseURL: config.effectiveBaseURL)
        case .anthropic:
            return AnthropicLLMService(apiKey: apiKey ?? "", model: config.model)
        case .google:
            return GoogleLLMService(apiKey: apiKey ?? "", model: config.model)
        case .perplexity:
            return PerplexityLLMService(apiKey: apiKey ?? "", model: config.model)
        }
    }
}
