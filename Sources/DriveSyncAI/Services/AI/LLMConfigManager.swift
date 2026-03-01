// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Security

@MainActor
final class LLMConfigManager: ObservableObject {
    @Published var activeProvider: LLMProviderType = .ollama
    @Published var activeModel: String = "llama3.2"
    @Published var isConfigured: Bool = false
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var customBaseURL: String?

    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case connected
        case disconnected(String)

        var displayText: String {
            switch self {
            case .unknown: return "Not checked"
            case .checking: return "Checking..."
            case .connected: return "Connected"
            case .disconnected(let msg): return "Disconnected: \(msg)"
            }
        }
    }

    private let configDir: URL
    private let configFile: URL
    private static let keychainService = "com.amitchorasiya.drivesyncai"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".drivesyncai", isDirectory: true)
        configFile = configDir.appendingPathComponent("llm_config.json")
        loadConfig()
    }

    // MARK: - Config Persistence

    func saveConfig() {
        let config = LLMProviderConfig(
            provider: activeProvider,
            model: activeModel,
            baseURL: customBaseURL
        )
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
        } catch {
            print("Failed to save LLM config: \(error)")
        }
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(LLMProviderConfig.self, from: data) else {
            return
        }
        activeProvider = config.provider
        activeModel = config.model
        customBaseURL = config.baseURL
        isConfigured = true
    }

    // MARK: - Keychain API Key Storage

    func saveAPIKey(_ key: String, for provider: LLMProviderType) {
        let account = "llm_apikey_\(provider.rawValue)"
        deleteAPIKey(for: provider)

        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadAPIKey(for provider: LLMProviderType) -> String? {
        let account = "llm_apikey_\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey(for provider: LLMProviderType) {
        let account = "llm_apikey_\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasAPIKey(for provider: LLMProviderType) -> Bool {
        return loadAPIKey(for: provider) != nil
    }

    // MARK: - Service Factory

    func currentService() -> LLMServiceProtocol {
        let config = LLMProviderConfig(
            provider: activeProvider,
            model: activeModel,
            baseURL: customBaseURL
        )
        let apiKey = loadAPIKey(for: activeProvider)
        return LLMServiceFactory.create(config: config, apiKey: apiKey)
    }

    // MARK: - Connection Validation

    func validateConnection() async {
        connectionStatus = .checking
        let service = currentService()
        let isValid = await service.validateConnection()
        if isValid {
            connectionStatus = .connected
            isConfigured = true
            saveConfig()
        } else {
            connectionStatus = .disconnected("Could not reach \(activeProvider.displayName)")
        }
    }

    func fetchAvailableModels() async -> [String] {
        let service = currentService()
        return (try? await service.availableModels()) ?? activeProvider.knownModels
    }
}
