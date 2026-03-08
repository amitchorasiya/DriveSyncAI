// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor ModelAdvisorService {

    // MARK: - Domain Detection

    static let domainKeywords: [DocumentDomain: [(keyword: String, weight: Double)]] = [
        .financial: [
            ("tax", 3.0), ("TDS", 4.0), ("capital gains", 4.0), ("invoice", 3.0),
            ("stamp duty", 4.0), ("bank statement", 3.0), ("GST", 3.0),
            ("deduction", 2.5), ("receipt", 2.0), ("salary", 2.0), ("ITR", 4.0),
            ("Form 16", 4.0), ("1099", 4.0), ("W-2", 4.0), ("Schedule C", 4.0),
            ("depreciation", 3.0), ("amortization", 3.0), ("balance sheet", 3.5),
            ("1040", 4.0), ("AGI", 3.5), ("withholding", 3.0), ("refund", 2.5),
            ("interest income", 3.0), ("dividend", 2.5), ("capital loss", 3.5),
            ("filing status", 3.0), ("exemption", 2.5), ("adjusted gross", 3.5),
            ("Form 1098", 4.0), ("Form 5498", 4.0), ("IRA", 2.5), ("HSA", 3.0),
            ("profit", 2.0), ("loss", 1.5), ("expense", 2.0), ("payment", 1.5),
            ("gross income", 3.0), ("net income", 3.0), ("taxable", 3.0),
        ],
        .legal: [
            ("whereas", 3.0), ("hereinafter", 3.5), ("indemnify", 3.0),
            ("agreement", 2.0), ("deed", 3.0), ("jurisdiction", 3.0),
            ("plaintiff", 3.5), ("defendant", 3.5), ("arbitration", 3.0),
            ("witness", 2.0), ("notarized", 3.0), ("affidavit", 3.5),
            ("covenant", 3.0), ("lien", 3.0), ("escrow", 3.0),
            ("conveyance", 3.5), ("mortgage", 2.5), ("encumbrance", 3.0),
            ("registration", 2.0), ("power of attorney", 3.5),
            ("clause", 2.0), ("provision", 2.0), ("obligation", 2.5),
            ("breach", 3.0), ("remedy", 2.5), ("damages", 3.0),
        ],
        .medical: [
            ("diagnosis", 3.0), ("prescription", 3.0), ("dosage", 3.5),
            ("patient", 2.5), ("ICD-10", 4.0), ("CPT", 4.0), ("mg", 1.5),
            ("lab report", 3.0), ("MRI", 3.0), ("blood test", 3.0),
            ("physician", 2.5), ("hospital", 2.0), ("insurance claim", 3.0),
            ("copay", 3.0), ("deductible", 2.0), ("provider", 2.0),
            ("treatment", 2.5), ("procedure", 2.5), ("radiology", 3.0),
            ("pathology", 3.0), ("vitals", 2.5), ("hemoglobin", 3.0),
        ],
        .technical: [
            ("specification", 2.5), ("datasheet", 3.0), ("schematic", 3.5),
            ("voltage", 3.0), ("frequency", 2.5), ("tolerance", 2.5),
            ("firmware", 3.0), ("protocol", 2.0), ("interface", 2.0),
            ("dimension", 2.0), ("material", 2.0), ("compliance", 2.5),
            ("revision", 2.0), ("assembly", 2.5),
        ],
        .academic: [
            ("abstract", 2.5), ("methodology", 3.0), ("hypothesis", 3.5),
            ("peer review", 3.5), ("citation", 2.5), ("bibliography", 3.0),
            ("thesis", 3.0), ("dissertation", 3.5), ("semester", 2.5),
            ("GPA", 3.0), ("transcript", 3.0), ("curriculum", 2.5),
            ("research", 2.0), ("journal", 2.0), ("conference", 2.0),
        ],
    ]

    func detectDomain(from corpus: DocumentCorpus) -> (domain: DocumentDomain, confidence: Double) {
        let allText = corpus.successfulDocuments
            .map { $0.extractedText.lowercased() }
            .joined(separator: " ")

        guard !allText.isEmpty else {
            return (.general, 0)
        }

        var scores: [DocumentDomain: Double] = [:]

        for (domain, keywords) in Self.domainKeywords {
            var totalScore: Double = 0
            for (keyword, weight) in keywords {
                let count = countOccurrences(of: keyword.lowercased(), in: allText)
                totalScore += Double(count) * weight
            }
            scores[domain] = totalScore
        }

        let maxScore = scores.values.max() ?? 0
        let totalScore = scores.values.reduce(0, +)

        guard maxScore > 5, totalScore > 0 else {
            return (.general, 0)
        }

        let topDomain = scores.max(by: { $0.value < $1.value })!
        let confidence = min(topDomain.value / max(totalScore, 1), 1.0)

        let sortedScores = scores.sorted { $0.value > $1.value }
        if sortedScores.count >= 2 {
            let ratio = sortedScores[0].value / max(sortedScores[1].value, 1)
            if ratio < 1.5 {
                return (.mixed, confidence * 0.6)
            }
        }

        return (topDomain.key, confidence)
    }

    // MARK: - Model Recommendation

    func recommend(
        domain: DocumentDomain,
        corpusStats: DocumentCorpus,
        currentConfig: LLMProviderConfig
    ) async -> ModelRecommendation? {
        let currentModel = currentConfig.model
        let currentProvider = currentConfig.provider.rawValue

        let (recommendedModel, recommendedProvider, reason) = bestModelForDomain(
            domain, corpusSize: corpusStats.totalChars, ocrRatio: ocrRatio(corpusStats)
        )

        if recommendedModel.lowercased() == currentModel.lowercased() {
            return nil
        }

        var isInstalled = false
        var pullCommand: String?
        var ollamaNotInstalled = false

        if recommendedProvider == "ollama" {
            let ollamaAvailable = Self.ollamaBinaryAvailable()
            if !ollamaAvailable {
                ollamaNotInstalled = true
            } else {
                let installed = await getInstalledOllamaModels()
                isInstalled = installed.contains(where: { $0.lowercased().hasPrefix(recommendedModel.lowercased()) })
                if !isInstalled {
                    pullCommand = "ollama pull \(recommendedModel)"
                }
            }
        } else {
            isInstalled = true
        }

        let alternatives = alternativeModels(for: domain)

        return ModelRecommendation(
            currentModel: currentModel,
            currentProvider: currentProvider,
            recommendedModel: recommendedModel,
            recommendedProvider: recommendedProvider,
            reason: reason,
            isInstalled: isInstalled,
            pullCommand: pullCommand,
            ollamaNotInstalled: ollamaNotInstalled,
            confidenceScore: 0.8,
            alternatives: alternatives
        )
    }

    private func bestModelForDomain(
        _ domain: DocumentDomain,
        corpusSize: Int,
        ocrRatio: Double
    ) -> (model: String, provider: String, reason: String) {
        if ocrRatio > 0.5 {
            return ("qwen2.5vl:7b", "ollama",
                    "Over half your documents were OCR'd from images. A vision-capable model can better interpret document layouts and handwriting.")
        }

        let needsLargeContext = corpusSize > 100_000

        switch domain {
        case .financial:
            if needsLargeContext {
                return ("mistral-nemo", "ollama",
                        "Your financial documents are extensive. Mistral Nemo's 128K context window can process them in fewer passes for better accuracy.")
            }
            return ("deepseek-r1:14b", "ollama",
                    "Your documents appear to be financial/tax related. DeepSeek-R1 excels at step-by-step numerical reasoning and calculation accuracy.")
        case .legal:
            return ("command-r", "ollama",
                    "Your documents appear to be legal in nature. Command-R is optimized for retrieval-augmented comprehension of long, complex documents.")
        case .medical:
            return ("phi4", "ollama",
                    "Your documents appear to be medical in nature. Phi-4 provides strong reasoning capabilities at moderate size for accurate medical document analysis.")
        case .technical:
            return ("gemma3:12b", "ollama",
                    "Your technical documents benefit from Gemma 3's balanced quality and structured output capabilities.")
        case .academic:
            return ("llama3.1:8b", "ollama",
                    "Llama 3.1 provides excellent instruction following for academic document analysis and summarization.")
        case .mixed, .general:
            return ("gemma3:12b", "ollama",
                    "For mixed document types, Gemma 3 offers the best balance of quality and speed across diverse content.")
        }
    }

    private func alternativeModels(for domain: DocumentDomain) -> [(model: String, reason: String)] {
        switch domain {
        case .financial:
            return [
                ("GPT-4o (OpenAI)", "Highest accuracy for numerical analysis and tax calculations"),
                ("phi4-reasoning", "Strong reasoning in a more compact package"),
            ]
        case .legal:
            return [
                ("Claude Sonnet (Anthropic)", "200K context window handles very long contracts"),
                ("llama3.1:70b", "Excellent comprehension for complex legal language"),
            ]
        case .medical:
            return [
                ("GPT-4o (OpenAI)", "Strong domain accuracy and safety for medical content"),
                ("llama3.1:8b", "Good general comprehension at moderate size"),
            ]
        default:
            return [
                ("GPT-4o-mini (OpenAI)", "Cost-effective cloud option for general analysis"),
                ("Gemini Flash (Google)", "1M context window for very large document sets"),
            ]
        }
    }

    // MARK: - Ollama Integration

    private static func ollamaBinaryAvailable() -> Bool {
        FileManager.default.fileExists(atPath: "/usr/local/bin/ollama")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
    }

    private func getInstalledOllamaModels() async -> [String] {
        guard Self.ollamaBinaryAvailable() else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        if !FileManager.default.fileExists(atPath: "/usr/local/bin/ollama") {
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        }

        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.components(separatedBy: .newlines)
                .dropFirst()
                .compactMap { line -> String? in
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                    return parts.first?.isEmpty == false ? parts.first : nil
                }
        } catch {
            return []
        }
    }

    // MARK: - Utilities

    private func countOccurrences(of search: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: search, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private func ocrRatio(_ corpus: DocumentCorpus) -> Double {
        guard corpus.supportedFileCount > 0 else { return 0 }
        return Double(corpus.ocrDocCount) / Double(corpus.supportedFileCount)
    }
}
