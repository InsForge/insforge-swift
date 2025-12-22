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

        return try response.decode(ChatCompletionResponse.self)
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

        return try response.decode(ListModelsResponse.self)
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
    public let success: Bool
    public let content: String
    public let metadata: Metadata?

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
    public let model: String
    public let images: [ImageMessage]
    public let text: String?
    public let count: Int
    public let metadata: Metadata?

    public struct Metadata: Codable, Sendable {
        public let model: String
        public let revisedPrompt: String?
        public let usage: TokenUsage?
    }
}

/// Image message
public struct ImageMessage: Codable, Sendable {
    public let type: String
    public let imageUrl: ImageURL

    public struct ImageURL: Codable, Sendable {
        public let url: String

        enum CodingKeys: String, CodingKey {
            case url
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
    }
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
    public let name: String
    public let description: String?
    public let contextLength: Int?
    public let maxCompletionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case contextLength = "context_length"
        case maxCompletionTokens = "max_completion_tokens"
    }
}
