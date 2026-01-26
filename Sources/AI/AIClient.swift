import Foundation
import InsForgeCore
import Logging

/// AI client for chat and image generation
public actor AIClient {
    private let url: URL
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private let tokenRefreshHandler: (any TokenRefreshHandler)?
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    public init(
        url: URL,
        headersProvider: LockIsolated<[String: String]>,
        tokenRefreshHandler: (any TokenRefreshHandler)? = nil
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = HTTPClient()
        self.tokenRefreshHandler = tokenRefreshHandler
    }

    /// Helper to execute HTTP request with optional auto-refresh
    private func executeRequest(
        _ method: HTTPMethod,
        url: URL,
        headers: [String: String],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        if let handler = tokenRefreshHandler {
            return try await httpClient.executeWithAutoRefresh(
                method,
                url: url,
                headers: headers,
                body: body,
                refreshHandler: handler
            )
        } else {
            return try await httpClient.execute(
                method,
                url: url,
                headers: headers,
                body: body
            )
        }
    }

    // MARK: - Chat Completion

    /// Generate chat completion
    /// - Parameters:
    ///   - model: OpenRouter model identifier (e.g., "openai/gpt-4")
    ///   - messages: Array of chat messages
    ///   - stream: Enable streaming response via Server-Sent Events
    ///   - temperature: Controls randomness in generation (0-2)
    ///   - maxTokens: Maximum number of tokens to generate
    ///   - topP: Nucleus sampling parameter (0-1)
    ///   - systemPrompt: System prompt to guide model behavior
    ///   - webSearch: Web search plugin configuration
    ///   - fileParser: File parser plugin configuration for PDFs
    ///   - thinking: Enable extended reasoning capabilities (Anthropic models only)
    public func chatCompletion(
        model: String,
        messages: [ChatMessage],
        stream: Bool = false,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        systemPrompt: String? = nil,
        webSearch: WebSearchPlugin? = nil,
        fileParser: FileParserPlugin? = nil,
        thinking: Bool? = nil
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
        if let webSearch = webSearch {
            body["webSearch"] = webSearch.toDictionary()
        }
        if let fileParser = fileParser {
            body["fileParser"] = fileParser.toDictionary()
        }
        if let thinking = thinking {
            body["thinking"] = thinking
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await executeRequest(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        // Try decoding the response
        do {
            let result = try response.decode(ChatCompletionResponse.self)
            logger.debug("Chat completion successful, model: \(model)")
            return result
        } catch {
            logger.error("Failed to decode chat completion response: \(error)")
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
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await executeRequest(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let result = try response.decode(ImageGenerationResponse.self)
        logger.debug("Image generation successful, model: \(model), images: \(result.imageCount)")
        return result
    }

    // MARK: - Models

    // MARK: - Embeddings

    /// Generate embeddings for text input
    /// - Parameters:
    ///   - model: Embedding model identifier (e.g., "google/gemini-embedding-001")
    ///   - input: Single text string or array of text strings to embed
    ///   - encodingFormat: Format for embeddings output ("float" or "base64"), defaults to "float"
    ///   - dimensions: Optional number of dimensions for output embeddings (only supported by certain models)
    /// - Returns: Embeddings response containing the embedding vectors
    public func generateEmbeddings(
        model: String,
        input: EmbeddingsInput,
        encodingFormat: EmbeddingsEncodingFormat? = nil,
        dimensions: Int? = nil
    ) async throws -> EmbeddingsResponse {
        let endpoint = url.appendingPathComponent("embeddings")

        var body: [String: Any] = [
            "model": model,
            "input": input.toValue()
        ]

        if let encodingFormat = encodingFormat {
            body["encoding_format"] = encodingFormat.rawValue
        }
        if let dimensions = dimensions {
            body["dimensions"] = dimensions
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await executeRequest(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let result = try response.decode(EmbeddingsResponse.self)
        logger.debug("Embeddings generation successful, model: \(model), count: \(result.data.count)")
        return result
    }

    // MARK: - Models

    /// List available AI models
    public func listModels() async throws -> ListModelsResponse {
        let endpoint = url.appendingPathComponent("models")

        // Log request
        logger.debug("GET \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await executeRequest(
            .get,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        // API returns array of models directly
        let models = try response.decode([AIModel].self)

        // Organize models by modality
        let textModels = models.filter { $0.outputModality?.contains("text") ?? false }
        let imageModels = models.filter { $0.outputModality?.contains("image") ?? false }

        // Group by provider
        let textProviders = Dictionary(grouping: textModels) { $0.provider ?? "unknown" }
            .map { provider, models in
                ListModelsResponse.ModelProvider(
                    provider: provider,
                    configured: true,  // All returned models are configured
                    models: models
                )
            }

        let imageProviders = Dictionary(grouping: imageModels) { $0.provider ?? "unknown" }
            .map { provider, models in
                ListModelsResponse.ModelProvider(
                    provider: provider,
                    configured: true,
                    models: models
                )
            }

        logger.debug("Listed \(models.count) model(s): \(textModels.count) text, \(imageModels.count) image")
        return ListModelsResponse(text: textProviders, image: imageProviders)
    }
}

// MARK: - Plugin Models

/// Web search plugin configuration
public struct WebSearchPlugin: Codable, Sendable {
    public let enabled: Bool
    public let engine: Engine?
    public let maxResults: Int?
    public let searchPrompt: String?

    public enum Engine: String, Codable, Sendable {
        case native
        case exa
    }

    public init(
        enabled: Bool = true,
        engine: Engine? = nil,
        maxResults: Int? = nil,
        searchPrompt: String? = nil
    ) {
        self.enabled = enabled
        self.engine = engine
        self.maxResults = maxResults
        self.searchPrompt = searchPrompt
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["enabled": enabled]
        if let engine = engine {
            dict["engine"] = engine.rawValue
        }
        if let maxResults = maxResults {
            dict["maxResults"] = maxResults
        }
        if let searchPrompt = searchPrompt {
            dict["searchPrompt"] = searchPrompt
        }
        return dict
    }
}

/// File parser plugin configuration
public struct FileParserPlugin: Codable, Sendable {
    public let enabled: Bool
    public let pdf: PDFConfig?

    public struct PDFConfig: Codable, Sendable {
        public let engine: Engine?

        public enum Engine: String, Codable, Sendable {
            case pdfText = "pdf-text"
            case mistralOcr = "mistral-ocr"
            case native
        }

        public init(engine: Engine? = nil) {
            self.engine = engine
        }

        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [:]
            if let engine = engine {
                dict["engine"] = engine.rawValue
            }
            return dict
        }
    }

    public init(enabled: Bool = true, pdf: PDFConfig? = nil) {
        self.enabled = enabled
        self.pdf = pdf
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["enabled": enabled]
        if let pdf = pdf {
            dict["pdf"] = pdf.toDictionary()
        }
        return dict
    }
}

// MARK: - Chat Models

// MARK: Multimodal Content Types

/// Text content part
public struct TextContent: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    func toDictionary() -> [String: Any] {
        [
            "type": "text",
            "text": text
        ]
    }
}

/// Image detail level for vision models
public enum ImageDetail: String, Sendable {
    case auto
    case low
    case high
}

/// Image content part
public struct ImageContent: Sendable {
    public let url: String
    public let detail: ImageDetail?

    /// Create image content from URL or base64 data URI
    /// - Parameters:
    ///   - url: Public URL (e.g., "https://example.com/image.jpg") or base64 data URI (e.g., "data:image/jpeg;base64,...")
    ///   - detail: Optional detail level for vision processing
    public init(url: String, detail: ImageDetail? = nil) {
        self.url = url
        self.detail = detail
    }

    func toDictionary() -> [String: Any] {
        var imageUrl: [String: Any] = ["url": url]
        if let detail = detail {
            imageUrl["detail"] = detail.rawValue
        }
        return [
            "type": "image_url",
            "image_url": imageUrl
        ]
    }
}

/// Audio format for input audio
public enum AudioFormat: String, Sendable {
    case wav
    case mp3
    case aiff
    case aac
    case ogg
    case flac
    case m4a
}

/// Audio content part
public struct AudioContent: Sendable {
    public let data: String
    public let format: AudioFormat

    /// Create audio content from base64-encoded audio data
    /// - Parameters:
    ///   - data: Base64-encoded audio data (direct URLs not supported for audio)
    ///   - format: Audio format
    public init(data: String, format: AudioFormat) {
        self.data = data
        self.format = format
    }

    func toDictionary() -> [String: Any] {
        [
            "type": "input_audio",
            "input_audio": [
                "data": data,
                "format": format.rawValue
            ]
        ]
    }
}

/// File content part for PDFs and other documents
public struct FileContent: Sendable {
    public let filename: String
    public let fileData: String

    /// Create file content
    /// - Parameters:
    ///   - filename: Filename with extension (e.g., "document.pdf")
    ///   - fileData: Public URL (e.g., "https://example.com/doc.pdf") or base64 data URL (e.g., "data:application/pdf;base64,...")
    public init(filename: String, fileData: String) {
        self.filename = filename
        self.fileData = fileData
    }

    func toDictionary() -> [String: Any] {
        [
            "type": "file",
            "file": [
                "filename": filename,
                "file_data": fileData
            ]
        ]
    }
}

/// Content part for multimodal messages
public enum ContentPart: Sendable {
    case text(TextContent)
    case image(ImageContent)
    case audio(AudioContent)
    case file(FileContent)

    /// Convenience initializer for text content
    public static func text(_ text: String) -> ContentPart {
        .text(TextContent(text: text))
    }

    /// Convenience initializer for image content
    public static func image(url: String, detail: ImageDetail? = nil) -> ContentPart {
        .image(ImageContent(url: url, detail: detail))
    }

    /// Convenience initializer for audio content
    public static func audio(data: String, format: AudioFormat) -> ContentPart {
        .audio(AudioContent(data: data, format: format))
    }

    /// Convenience initializer for file content
    public static func file(filename: String, fileData: String) -> ContentPart {
        .file(FileContent(filename: filename, fileData: fileData))
    }

    func toDictionary() -> [String: Any] {
        switch self {
        case .text(let content):
            return content.toDictionary()
        case .image(let content):
            return content.toDictionary()
        case .audio(let content):
            return content.toDictionary()
        case .file(let content):
            return content.toDictionary()
        }
    }
}

/// Message content - can be simple string or array of content parts for multimodal
public enum MessageContent: Sendable {
    case text(String)
    case parts([ContentPart])

    func toValue() -> Any {
        switch self {
        case .text(let string):
            return string
        case .parts(let parts):
            return parts.map { $0.toDictionary() }
        }
    }
}

/// Chat message with multimodal support
public struct ChatMessage: Sendable {
    public let role: Role
    public let content: MessageContent

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    /// Create a simple text message
    public init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }

    /// Create a multimodal message with content parts
    public init(role: Role, content: [ContentPart]) {
        self.role = role
        self.content = .parts(content)
    }

    func toDictionary() -> [String: Any] {
        [
            "role": role.rawValue,
            "content": content.toValue()
        ]
    }
}

/// Chat completion response
public struct ChatCompletionResponse: Codable, Sendable {
    public let text: String
    public let annotations: [UrlCitationAnnotation]?
    public let metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case text
        case annotations
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

/// URL citation annotation from web search results
public struct UrlCitationAnnotation: Codable, Sendable {
    public let type: String
    public let urlCitation: UrlCitation?

    public struct UrlCitation: Codable, Sendable {
        public let url: String
        public let title: String?
        public let content: String?
        public let startIndex: Int?
        public let endIndex: Int?
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
    public let modelId: String?
    public let provider: String?
    public let inputModality: [String]?
    public let outputModality: [String]?
    public let priceLevel: Int?

    // Computed properties for compatibility
    public var name: String { id }
    public var description: String? { nil }
    public var contextLength: Int? { nil }
    public var maxCompletionTokens: Int? { nil }
}

// MARK: - Embeddings Models

/// Input type for embeddings - supports single string or array of strings
public enum EmbeddingsInput: Sendable {
    case single(String)
    case multiple([String])

    func toValue() -> Any {
        switch self {
        case .single(let text):
            return text
        case .multiple(let texts):
            return texts
        }
    }
}

/// Encoding format for embeddings output
public enum EmbeddingsEncodingFormat: String, Codable, Sendable {
    case float
    case base64
}

/// Embeddings response
public struct EmbeddingsResponse: Codable, Sendable {
    public let object: String
    public let data: [EmbeddingObject]
    public let metadata: Metadata?

    public struct Metadata: Codable, Sendable {
        public let model: String
        public let usage: EmbeddingsUsage?
    }
}

/// Token usage for embeddings (may not have completionTokens)
public struct EmbeddingsUsage: Codable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
}

/// Individual embedding object
public struct EmbeddingObject: Codable, Sendable {
    public let object: String
    public let embedding: [Double]
    public let index: Int
}
