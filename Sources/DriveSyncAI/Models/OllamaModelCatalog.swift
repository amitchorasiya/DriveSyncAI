// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct OllamaModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let description: String
    let sizes: [String]
    let category: OllamaModelCategory
    let recommended: Bool
    let pullCommand: String

    init(id: String, displayName: String, description: String, sizes: [String], category: OllamaModelCategory, recommended: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.sizes = sizes
        self.category = category
        self.recommended = recommended
        self.pullCommand = "ollama pull \(id)"
    }
}

enum OllamaModelCategory: String, CaseIterable, Identifiable {
    case generalPurpose = "General Purpose"
    case reasoning = "Reasoning"
    case coding = "Coding"
    case vision = "Vision"
    case lightweight = "Lightweight / Edge"
    case multilingual = "Multilingual"
    case embedding = "Embedding"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generalPurpose: return "brain.head.profile"
        case .reasoning: return "lightbulb.max"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .vision: return "eye"
        case .lightweight: return "bolt"
        case .multilingual: return "globe"
        case .embedding: return "square.3.layers.3d"
        }
    }
}

enum OllamaModelCatalog {
    static let all: [OllamaModel] = generalPurpose + reasoning + coding + vision + lightweight + multilingual + embedding

    static let generalPurpose: [OllamaModel] = [
        OllamaModel(
            id: "llama3.2", displayName: "Llama 3.2",
            description: "Meta's latest compact model. Best balance of speed and quality for file organization.",
            sizes: ["1B", "3B"], category: .generalPurpose, recommended: true
        ),
        OllamaModel(
            id: "llama3.1", displayName: "Llama 3.1",
            description: "Meta's flagship open model. Excellent instruction following.",
            sizes: ["8B", "70B", "405B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "llama3.3", displayName: "Llama 3.3",
            description: "70B model with performance comparable to Llama 3.1 405B at lower cost.",
            sizes: ["70B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "llama4", displayName: "Llama 4",
            description: "Meta's newest generation with improved reasoning and instruction following.",
            sizes: ["Scout 109B", "Maverick 402B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "gemma3", displayName: "Gemma 3",
            description: "Google's most capable model that fits on a single GPU. Strong at structured output.",
            sizes: ["1B", "4B", "12B", "27B"], category: .generalPurpose, recommended: true
        ),
        OllamaModel(
            id: "gemma2", displayName: "Gemma 2",
            description: "Google's efficient open model family with strong general capabilities.",
            sizes: ["2B", "9B", "27B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "qwen3", displayName: "Qwen 3",
            description: "Alibaba's latest model with strong multilingual and reasoning abilities.",
            sizes: ["0.6B", "1.7B", "4B", "8B", "14B", "32B", "235B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "qwen2.5", displayName: "Qwen 2.5",
            description: "Versatile model family from Alibaba. Good at structured JSON output.",
            sizes: ["0.5B", "1.5B", "3B", "7B", "14B", "32B", "72B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mistral", displayName: "Mistral 7B",
            description: "Mistral AI's foundational 7B model. Fast and efficient.",
            sizes: ["7B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mistral-nemo", displayName: "Mistral Nemo",
            description: "12B model from Mistral AI with 128K context window.",
            sizes: ["12B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mistral-small", displayName: "Mistral Small",
            description: "Mistral's efficient model optimized for low-latency tasks.",
            sizes: ["22B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mistral-small3.2", displayName: "Mistral Small 3.2",
            description: "Latest Mistral small model with vision capabilities.",
            sizes: ["24B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mistral-large", displayName: "Mistral Large",
            description: "Mistral's most capable model for complex tasks.",
            sizes: ["123B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "mixtral", displayName: "Mixtral 8x7B",
            description: "Mixture-of-experts model. Uses only 12B active params from 46B total.",
            sizes: ["8x7B", "8x22B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "phi4", displayName: "Phi-4",
            description: "Microsoft's state-of-the-art 14B model. Excellent reasoning for its size.",
            sizes: ["14B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "phi3", displayName: "Phi-3",
            description: "Microsoft's compact model with strong performance.",
            sizes: ["3.8B", "14B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "phi3.5", displayName: "Phi-3.5",
            description: "Updated Phi-3 with improved reasoning and 128K context.",
            sizes: ["3.8B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "command-r", displayName: "Command R",
            description: "Cohere's model optimized for RAG and tool use.",
            sizes: ["35B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "command-r-plus", displayName: "Command R+",
            description: "Cohere's largest model for complex reasoning and generation.",
            sizes: ["104B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "gpt-oss", displayName: "GPT-OSS",
            description: "OpenAI's open-weight models for reasoning and agentic tasks.",
            sizes: ["20B", "120B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "granite3.3", displayName: "Granite 3.3",
            description: "IBM's enterprise-grade model with strong structured output.",
            sizes: ["2B", "8B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "granite4", displayName: "Granite 4",
            description: "IBM's latest generation enterprise model.",
            sizes: ["8B", "32B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "olmo2", displayName: "OLMo 2",
            description: "Allen AI's fully open model with open training data and code.",
            sizes: ["7B", "13B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "hermes3", displayName: "Hermes 3",
            description: "Nous Research's instruction-tuned model. Great at function calling.",
            sizes: ["8B", "70B", "405B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "dolphin3", displayName: "Dolphin 3",
            description: "Uncensored, general-purpose assistant model.",
            sizes: ["8B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "falcon3", displayName: "Falcon 3",
            description: "TII's latest open model with competitive performance.",
            sizes: ["1B", "3B", "7B", "10B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "wizardlm2", displayName: "WizardLM 2",
            description: "Microsoft's instruction-following model.",
            sizes: ["7B", "8x22B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "glm4", displayName: "GLM-4",
            description: "Tsinghua's bilingual model with strong Chinese and English support.",
            sizes: ["9B"], category: .generalPurpose
        ),
        OllamaModel(
            id: "exaone3.5", displayName: "EXAONE 3.5",
            description: "LG AI Research's bilingual (English/Korean) model.",
            sizes: ["2.4B", "7.8B", "32B"], category: .generalPurpose
        ),
    ]

    static let reasoning: [OllamaModel] = [
        OllamaModel(
            id: "deepseek-r1", displayName: "DeepSeek-R1",
            description: "State-of-the-art reasoning model. Comparable to OpenAI o1. Thinks step-by-step.",
            sizes: ["1.5B", "7B", "8B", "14B", "32B", "70B", "671B"], category: .reasoning, recommended: true
        ),
        OllamaModel(
            id: "qwq", displayName: "QwQ",
            description: "Alibaba's reasoning model with chain-of-thought capabilities.",
            sizes: ["32B"], category: .reasoning
        ),
        OllamaModel(
            id: "phi4-reasoning", displayName: "Phi-4 Reasoning",
            description: "Microsoft's reasoning-focused Phi-4 variant.",
            sizes: ["14B"], category: .reasoning
        ),
        OllamaModel(
            id: "deepscaler", displayName: "DeepScaleR",
            description: "Compact reasoning model fine-tuned for step-by-step problem solving.",
            sizes: ["1.5B"], category: .reasoning
        ),
        OllamaModel(
            id: "openthinker", displayName: "OpenThinker",
            description: "Open reasoning model optimized for logical deduction.",
            sizes: ["7B", "32B"], category: .reasoning
        ),
        OllamaModel(
            id: "cogito", displayName: "Cogito",
            description: "Reasoning-enhanced model that can toggle between fast and deep thinking.",
            sizes: ["3B", "8B", "14B", "32B", "70B"], category: .reasoning
        ),
        OllamaModel(
            id: "magistral", displayName: "Magistral",
            description: "Mistral AI's reasoning model with structured thinking.",
            sizes: ["8B", "24B"], category: .reasoning
        ),
        OllamaModel(
            id: "marco-o1", displayName: "Marco-o1",
            description: "Alibaba's reasoning model inspired by o1-style thinking.",
            sizes: ["7B"], category: .reasoning
        ),
    ]

    static let coding: [OllamaModel] = [
        OllamaModel(
            id: "qwen2.5-coder", displayName: "Qwen 2.5 Coder",
            description: "Alibaba's code-specialized model. Strong at code generation and understanding.",
            sizes: ["0.5B", "1.5B", "3B", "7B", "14B", "32B"], category: .coding
        ),
        OllamaModel(
            id: "qwen3-coder", displayName: "Qwen 3 Coder",
            description: "Latest coding model from Alibaba for agentic and code tasks.",
            sizes: ["30B", "480B"], category: .coding
        ),
        OllamaModel(
            id: "deepseek-coder", displayName: "DeepSeek Coder",
            description: "Code-focused model trained on 2T tokens of code data.",
            sizes: ["1.3B", "6.7B", "33B"], category: .coding
        ),
        OllamaModel(
            id: "deepseek-coder-v2", displayName: "DeepSeek Coder V2",
            description: "Upgraded coding model with mixture-of-experts architecture.",
            sizes: ["16B", "236B"], category: .coding
        ),
        OllamaModel(
            id: "codellama", displayName: "Code Llama",
            description: "Meta's code-specialized Llama model. Good for code completion.",
            sizes: ["7B", "13B", "34B", "70B"], category: .coding
        ),
        OllamaModel(
            id: "codegemma", displayName: "CodeGemma",
            description: "Google's code-focused Gemma variant.",
            sizes: ["2B", "7B"], category: .coding
        ),
        OllamaModel(
            id: "codestral", displayName: "Codestral",
            description: "Mistral AI's dedicated coding model with 32K context.",
            sizes: ["22B"], category: .coding
        ),
        OllamaModel(
            id: "devstral", displayName: "Devstral",
            description: "Mistral's agentic coding model for software engineering tasks.",
            sizes: ["24B"], category: .coding
        ),
        OllamaModel(
            id: "starcoder2", displayName: "StarCoder 2",
            description: "BigCode's code model trained on 600+ programming languages.",
            sizes: ["3B", "7B", "15B"], category: .coding
        ),
        OllamaModel(
            id: "yi-coder", displayName: "Yi Coder",
            description: "01.AI's code-specialized model.",
            sizes: ["1.5B", "9B"], category: .coding
        ),
        OllamaModel(
            id: "opencoder", displayName: "OpenCoder",
            description: "Fully open code model with transparent training data.",
            sizes: ["1.5B", "8B"], category: .coding
        ),
        OllamaModel(
            id: "granite-code", displayName: "Granite Code",
            description: "IBM's enterprise coding model for code generation and review.",
            sizes: ["3B", "8B", "20B", "34B"], category: .coding
        ),
        OllamaModel(
            id: "deepcoder", displayName: "DeepCoder",
            description: "Reasoning-enhanced coding model.",
            sizes: ["14B"], category: .coding
        ),
    ]

    static let vision: [OllamaModel] = [
        OllamaModel(
            id: "llava", displayName: "LLaVA",
            description: "Visual instruction-tuned model. Understands images and answers questions about them.",
            sizes: ["7B", "13B", "34B"], category: .vision
        ),
        OllamaModel(
            id: "llama3.2-vision", displayName: "Llama 3.2 Vision",
            description: "Meta's multimodal model supporting image understanding.",
            sizes: ["11B", "90B"], category: .vision
        ),
        OllamaModel(
            id: "qwen3-vl", displayName: "Qwen3 VL",
            description: "Alibaba's most powerful vision-language model.",
            sizes: ["2B", "8B", "32B", "235B"], category: .vision
        ),
        OllamaModel(
            id: "qwen2.5vl", displayName: "Qwen 2.5 VL",
            description: "Strong vision-language model with document understanding.",
            sizes: ["3B", "7B", "32B", "72B"], category: .vision
        ),
        OllamaModel(
            id: "minicpm-v", displayName: "MiniCPM-V",
            description: "Compact vision model that runs efficiently on edge devices.",
            sizes: ["8B"], category: .vision
        ),
        OllamaModel(
            id: "granite3.2-vision", displayName: "Granite 3.2 Vision",
            description: "IBM's enterprise vision model for document and image analysis.",
            sizes: ["2B"], category: .vision
        ),
        OllamaModel(
            id: "moondream", displayName: "Moondream",
            description: "Tiny but capable vision model. Runs on minimal hardware.",
            sizes: ["1.8B"], category: .vision
        ),
        OllamaModel(
            id: "bakllava", displayName: "BakLLaVA",
            description: "Enhanced LLaVA variant with improved visual understanding.",
            sizes: ["7B"], category: .vision
        ),
        OllamaModel(
            id: "gemma3n", displayName: "Gemma 3n",
            description: "Google's efficient multimodal model for on-device vision tasks.",
            sizes: ["E2B", "E4B"], category: .vision
        ),
    ]

    static let lightweight: [OllamaModel] = [
        OllamaModel(
            id: "qwen2.5:1.5b-instruct", displayName: "Qwen 2.5 1.5B Instruct",
            description: "Default local model. Best structured JSON output for its size. Apache 2.0 license. ~986 MB.",
            sizes: ["1.5B"], category: .lightweight, recommended: true
        ),
        OllamaModel(
            id: "phi4-mini", displayName: "Phi-4 Mini",
            description: "Microsoft's smallest Phi-4. Ideal for fast local inference.",
            sizes: ["3.8B"], category: .lightweight, recommended: true
        ),
        OllamaModel(
            id: "smollm2", displayName: "SmolLM 2",
            description: "Hugging Face's compact model family for on-device use.",
            sizes: ["135M", "360M", "1.7B"], category: .lightweight
        ),
        OllamaModel(
            id: "tinyllama", displayName: "TinyLlama",
            description: "1.1B model trained on 3T tokens. Surprisingly capable for its size.",
            sizes: ["1.1B"], category: .lightweight
        ),
        OllamaModel(
            id: "lfm2", displayName: "LFM 2",
            description: "Liquid AI's hybrid architecture model for on-device deployment.",
            sizes: ["1.2B", "3.2B"], category: .lightweight
        ),
        OllamaModel(
            id: "gemma", displayName: "Gemma",
            description: "Google's original lightweight model.",
            sizes: ["2B", "7B"], category: .lightweight
        ),
        OllamaModel(
            id: "qwen", displayName: "Qwen",
            description: "Alibaba's original compact model.",
            sizes: ["0.5B", "1.8B", "4B", "7B"], category: .lightweight
        ),
    ]

    static let multilingual: [OllamaModel] = [
        OllamaModel(
            id: "aya", displayName: "Aya",
            description: "Cohere's multilingual model supporting 100+ languages.",
            sizes: ["8B", "35B"], category: .multilingual
        ),
        OllamaModel(
            id: "aya-expanse", displayName: "Aya Expanse",
            description: "Expanded multilingual model with improved performance across languages.",
            sizes: ["8B", "32B"], category: .multilingual
        ),
        OllamaModel(
            id: "llama2-chinese", displayName: "Llama 2 Chinese",
            description: "Llama 2 fine-tuned for Chinese language tasks.",
            sizes: ["7B", "13B"], category: .multilingual
        ),
        OllamaModel(
            id: "yi", displayName: "Yi",
            description: "01.AI's bilingual (English/Chinese) model family.",
            sizes: ["6B", "9B", "34B"], category: .multilingual
        ),
        OllamaModel(
            id: "sailor2", displayName: "Sailor 2",
            description: "Multilingual model for Southeast Asian languages.",
            sizes: ["1B", "8B", "20B"], category: .multilingual
        ),
    ]

    static let embedding: [OllamaModel] = [
        OllamaModel(
            id: "nomic-embed-text", displayName: "Nomic Embed Text",
            description: "High-performance text embedding model with 8192 context length.",
            sizes: ["137M"], category: .embedding
        ),
        OllamaModel(
            id: "mxbai-embed-large", displayName: "mxbai Embed Large",
            description: "State-of-the-art embedding model for semantic search.",
            sizes: ["335M"], category: .embedding
        ),
        OllamaModel(
            id: "bge-m3", displayName: "BGE-M3",
            description: "Multi-functionality embedding model supporting dense, sparse, and multi-vector retrieval.",
            sizes: ["567M"], category: .embedding
        ),
        OllamaModel(
            id: "snowflake-arctic-embed", displayName: "Snowflake Arctic Embed",
            description: "Snowflake's text embedding models optimized for retrieval.",
            sizes: ["22M", "33M", "110M", "137M", "335M"], category: .embedding
        ),
        OllamaModel(
            id: "all-minilm", displayName: "All-MiniLM",
            description: "Compact sentence embedding model for similarity tasks.",
            sizes: ["23M", "33M"], category: .embedding
        ),
    ]

    static func models(for category: OllamaModelCategory) -> [OllamaModel] {
        all.filter { $0.category == category }
    }

    static func model(withID id: String) -> OllamaModel? {
        all.first { $0.id == id }
    }

    static var recommendedModels: [OllamaModel] {
        all.filter { $0.recommended }
    }

    static var allModelIDs: [String] {
        all.map(\.id)
    }
}
