import Foundation
import InsForgeCore

/// AI client for chat and image generation
public actor AIClient {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let logger: (any InsForgeLogger)?

    public init(
        url: URL,
        headers: [String: String],
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.logger = logger
    }

    // MARK: - Chat Completion

    /// Generate chat completion
    public func chatCompletion(
        model: String,
        messages: [ChatMessage],
        stream: Bool = false,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        systemPrompt: String? = nil
    ) async throws -> ChatCompletionResponse {
        let endpoint = url.appendingPathComponent("chat/completion")

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.toDictionary() },
            "stream": stream
        ]

        if let temperature = temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = maxTokens {
            body["maxTokens"] = maxTokens
        }
        if let topP = topP {
            body["topP"] = topP
        }
        if let systemPrompt = systemPrompt {
            body["systemPrompt"] = systemPrompt
        }

        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        // Try decoding the response
        do {
            return try response.decode(ChatCompletionResponse.self)
        } catch {
            logger?.log("[ChatCompletion] Failed to decode response: \(error)")
            logger?.log("[ChatCompletion] Response data: \(String(data: response.data, encoding: .utf8) ?? "unable to decode")")
            throw error
        }
    }

    // MARK: - Image Generation

    /// Generate images
    public func generateImage(
        model: String,
        prompt: String
    ) async throws -> ImageGenerationResponse {
        let endpoint = url.appendingPathComponent("image/generation")

        let body: [String: String] = [
            "model": model,
            "prompt": prompt
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        return try response.decode(ImageGenerationResponse.self)
    }

    // MARK: - Models

    /// List available AI models
    public func listModels() async throws -> ListModelsResponse {
        let endpoint = url.appendingPathComponent("models")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // API returns array of models directly
        let models = try response.decode([AIModel].self)

        // Organize models by modality
        let textModels = models.filter { $0.outputModality.contains("text") }
        let imageModels = models.filter { $0.outputModality.contains("image") }

        // Group by provider
        let textProviders = Dictionary(grouping: textModels) { $0.provider }
            .map { provider, models in
                ListModelsResponse.ModelProvider(
                    provider: provider,
                    configured: true,  // All returned models are configured
                    models: models
                )
            }

        let imageProviders = Dictionary(grouping: imageModels) { $0.provider }
            .map { provider, models in
                ListModelsResponse.ModelProvider(
                    provider: provider,
                    configured: true,
                    models: models
                )
            }

        return ListModelsResponse(text: textProviders, image: imageProviders)
    }
}

// MARK: - Chat Models

/// Chat message
public struct ChatMessage: Codable, Sendable {
    public let role: Role
    public let content: String

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    func toDictionary() -> [String: String] {
        [
            "role": role.rawValue,
            "content": content
        ]
    }
}

/// Chat completion response
public struct ChatCompletionResponse: Codable, Sendable {
    public let text: String
    public let metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case text
        case metadata
    }

    // Computed properties for compatibility
    public var content: String { text }
    public var success: Bool { !text.isEmpty }

    public struct Metadata: Codable, Sendable {
        public let model: String
        public let usage: TokenUsage?
    }
}

/// Token usage information
public struct TokenUsage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

// MARK: - Image Models

/// Image generation response
public struct ImageGenerationResponse: Codable, Sendable {
    public let model: String?
    public let images: [ImageMessage]
    public let text: String?
    public let count: Int?
    public let metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case model
        case images
        case text
        case metadata
        case count
    }

    // Computed property for count compatibility
    public var imageCount: Int {
        count ?? images.count
    }

    public struct Metadata: Codable, Sendable {
        public let model: String
        public let revisedPrompt: String?
        public let usage: TokenUsage?
    }
}

/// Image message
public struct ImageMessage: Codable, Sendable {
    public let type: String
    public let imageUrl: String

    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl
    }

    // Computed property for compatibility
    public var url: String { imageUrl }
}

// MARK: - Models List

/// List models response
public struct ListModelsResponse: Codable, Sendable {
    public let text: [ModelProvider]
    public let image: [ModelProvider]

    public struct ModelProvider: Codable, Sendable {
        public let provider: String
        public let configured: Bool
        public let models: [AIModel]
    }
}

/// AI model information
public struct AIModel: Codable, Sendable {
    public let id: String
    public let modelId: String
    public let provider: String
    public let inputModality: [String]
    public let outputModality: [String]
    public let priceLevel: Int

    // Computed properties for compatibility
    public var name: String { id }
    public var description: String? { nil }
    public var contextLength: Int? { nil }
    public var maxCompletionTokens: Int? { nil }
}
