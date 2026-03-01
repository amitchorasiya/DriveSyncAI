// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum LLMProviderType: String, CaseIterable, Codable, Identifiable {
    case ollama
    case openai
    case anthropic
    case google
    case perplexity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google Gemini"
        case .perplexity: return "Perplexity"
        }
    }

    var requiresAPIKey: Bool { self != .ollama }

    var supportsStructuredOutput: Bool { self != .perplexity }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .openai: return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        case .google: return "https://generativelanguage.googleapis.com"
        case .perplexity: return "https://api.perplexity.ai"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .google: return "gemini-2.0-flash"
        case .perplexity: return "sonar"
        }
    }

    var knownModels: [String] {
        switch self {
        case .ollama: return OllamaModelCatalog.allModelIDs
        case .openai: return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic: return ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]
        case .google: return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro"]
        case .perplexity: return ["sonar", "sonar-pro", "sonar-reasoning"]
        }
    }

    var privacyNote: String {
        switch self {
        case .ollama: return "All processing happens on your Mac. No data leaves your device."
        default: return "File metadata (names, paths, sizes, types) is sent to \(displayName) servers. File contents are never transmitted."
        }
    }
}

struct LLMProviderConfig: Codable, Equatable {
    var provider: LLMProviderType
    var model: String
    var baseURL: String?

    init(provider: LLMProviderType = .ollama, model: String? = nil, baseURL: String? = nil) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.baseURL = baseURL
    }

    var effectiveBaseURL: String {
        baseURL ?? provider.defaultBaseURL
    }
}

struct LLMMessage: Codable {
    let role: String
    let content: String
}
