import XCTest
import TestHelper
@testable import InsForge
@testable import InsForgeAI
@testable import InsForgeCore

/// Tests for InsForge AI Client
///
/// ## Setup Instructions
/// These tests require AI providers to be configured in your InsForge instance.
/// Tests will be skipped if providers are not available.
///
/// ## What's tested:
/// - List available models (text and image)
/// - Chat completion with various models
/// - Image generation with various models
final class InsForgeAITests: XCTestCase {
    // MARK: - Helper

    private var insForgeClient: InsForgeClient!

    override func setUp() async throws {
        insForgeClient = TestHelper.createClient()
        print("📍 InsForge URL: \(TestHelper.insForgeURL)")
    }

    override func tearDown() async throws {
        insForgeClient = nil
    }

    // MARK: - Model Tests

    func testChatMessageCreation() {
        let message = ChatMessage(role: .user, content: "Hello, AI!")

        XCTAssertEqual(message.role, .user)

        let dict = message.toDictionary()
        XCTAssertEqual(dict["role"] as? String, "user")
        XCTAssertEqual(dict["content"] as? String, "Hello, AI!")
    }

    func testChatMessageRoles() {
        let userMessage = ChatMessage(role: .user, content: "Question")
        let assistantMessage = ChatMessage(role: .assistant, content: "Answer")
        let systemMessage = ChatMessage(role: .system, content: "Context")

        XCTAssertEqual(userMessage.role.rawValue, "user")
        XCTAssertEqual(assistantMessage.role.rawValue, "assistant")
        XCTAssertEqual(systemMessage.role.rawValue, "system")
    }

    // MARK: - Multimodal Message Tests

    func testMultimodalMessageWithImage() {
        let message = ChatMessage(role: .user, content: [
            .text("What is in this image?"),
            .image(url: "https://example.com/image.jpg", detail: .high)
        ])

        XCTAssertEqual(message.role, .user)

        let dict = message.toDictionary()
        XCTAssertEqual(dict["role"] as? String, "user")

        guard let contentArray = dict["content"] as? [[String: Any]] else {
            XCTFail("Content should be an array")
            return
        }

        XCTAssertEqual(contentArray.count, 2)

        // Check text part
        XCTAssertEqual(contentArray[0]["type"] as? String, "text")
        XCTAssertEqual(contentArray[0]["text"] as? String, "What is in this image?")

        // Check image part
        XCTAssertEqual(contentArray[1]["type"] as? String, "image_url")
        if let imageUrl = contentArray[1]["image_url"] as? [String: Any] {
            XCTAssertEqual(imageUrl["url"] as? String, "https://example.com/image.jpg")
            XCTAssertEqual(imageUrl["detail"] as? String, "high")
        } else {
            XCTFail("image_url should be a dictionary")
        }
    }

    func testMultimodalMessageWithFile() {
        let message = ChatMessage(role: .user, content: [
            .text("Summarize this document"),
            .file(filename: "doc.pdf", fileData: "https://example.com/doc.pdf")
        ])

        let dict = message.toDictionary()
        guard let contentArray = dict["content"] as? [[String: Any]] else {
            XCTFail("Content should be an array")
            return
        }

        XCTAssertEqual(contentArray.count, 2)

        // Check file part
        XCTAssertEqual(contentArray[1]["type"] as? String, "file")
        if let file = contentArray[1]["file"] as? [String: Any] {
            XCTAssertEqual(file["filename"] as? String, "doc.pdf")
            XCTAssertEqual(file["file_data"] as? String, "https://example.com/doc.pdf")
        } else {
            XCTFail("file should be a dictionary")
        }
    }

    func testMultimodalMessageWithAudio() {
        let message = ChatMessage(role: .user, content: [
            .text("Transcribe this audio"),
            .audio(data: "base64encodedaudiodata", format: .mp3)
        ])

        let dict = message.toDictionary()
        guard let contentArray = dict["content"] as? [[String: Any]] else {
            XCTFail("Content should be an array")
            return
        }

        XCTAssertEqual(contentArray.count, 2)

        // Check audio part
        XCTAssertEqual(contentArray[1]["type"] as? String, "input_audio")
        if let inputAudio = contentArray[1]["input_audio"] as? [String: Any] {
            XCTAssertEqual(inputAudio["data"] as? String, "base64encodedaudiodata")
            XCTAssertEqual(inputAudio["format"] as? String, "mp3")
        } else {
            XCTFail("input_audio should be a dictionary")
        }
    }

    // MARK: - API Tests

    func testAIClientInitialization() async {
        let aiClient = await insForgeClient.ai
        XCTAssertNotNil(aiClient)
    }

    /// Test listing available AI models
    func testListModels() async throws {
        print("🔵 Testing listModels...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        // Verify response structure
        XCTAssertNotNil(modelsResponse.text)
        XCTAssertNotNil(modelsResponse.image)

        print("✅ Found \(modelsResponse.text.count) text provider(s) and \(modelsResponse.image.count) image provider(s)")

        // Print text providers
        if !modelsResponse.text.isEmpty {
            print("   📝 Text Providers:")
            for provider in modelsResponse.text {
                print("      - \(provider.provider) (configured: \(provider.configured), models: \(provider.models.count))")
                for model in provider.models.prefix(3) {
                    print("        • \(model.name) (\(model.id))")
                }
            }
        }

        // Print image providers
        if !modelsResponse.image.isEmpty {
            print("   🎨 Image Providers:")
            for provider in modelsResponse.image {
                print("      - \(provider.provider) (configured: \(provider.configured), models: \(provider.models.count))")
                for model in provider.models.prefix(3) {
                    print("        • \(model.name) (\(model.id))")
                }
            }
        }
    }

    /// Test chat completion with basic parameters
    func testChatCompletion() async throws {
        print("🔵 Testing chatCompletion...")

        // Get available models
        let modelsResponse = try await insForgeClient.ai.listModels()

        // Find first configured text provider and model
        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        print("   Using model: \(firstModel.name) (\(firstModel.id))")

        // Create chat messages
        let messages = [
            ChatMessage(role: .user, content: "Say 'Hello from InsForge Swift SDK' in exactly those words.")
        ]

        // Call chat completion
        let response = try await insForgeClient.ai.chatCompletion(
            model: firstModel.id,
            messages: messages
        )

        // Verify response
        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)
        XCTAssertNotNil(response.metadata)

        print("✅ Chat completion successful")
        print("   Response: \(response.content)")
        if let metadata = response.metadata {
            print("   Model used: \(metadata.model)")
            if let usage = metadata.usage {
                print("   Tokens: \(usage.totalTokens) (prompt: \(usage.promptTokens), completion: \(usage.completionTokens))")
            }
        }
    }

    /// Test chat completion with parameters
    func testChatCompletionWithParameters() async throws {
        print("🔵 Testing chatCompletion with parameters...")

        // Get available models
        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        let messages = [
            ChatMessage(role: .user, content: "Write a haiku about Swift programming.")
        ]

        // Call with parameters
        let response = try await insForgeClient.ai.chatCompletion(
            model: firstModel.id,
            messages: messages,
            temperature: 0.7,
            maxTokens: 100,
            topP: 0.9,
            systemPrompt: "You are a helpful programming assistant."
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        print("✅ Chat completion with parameters successful")
        print("   Response: \(response.content)")
    }

    /// Test chat completion with conversation history
    func testChatCompletionWithHistory() async throws {
        print("🔵 Testing chatCompletion with conversation history...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        // Create conversation with history
        let messages = [
            ChatMessage(role: .user, content: "My name is Alice."),
            ChatMessage(role: .assistant, content: "Hello Alice! Nice to meet you."),
            ChatMessage(role: .user, content: "What is my name?")
        ]

        let response = try await insForgeClient.ai.chatCompletion(
            model: firstModel.id,
            messages: messages
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        // Response should mention Alice
        let containsAlice = response.content.lowercased().contains("alice")
        print("✅ Chat completion with history successful")
        print("   Response contains 'Alice': \(containsAlice)")
        print("   Response: \(response.content)")
    }

    // MARK: - Multimodal Chat Completion Tests

    /// Test chat completion with image input (vision)
    func testChatCompletionWithImage() async throws {
        print("🔵 Testing chatCompletion with image input...")

        // Get available models - need a vision-capable model
        let modelsResponse = try await insForgeClient.ai.listModels()

        // Look for a vision-capable model (e.g., gpt-4-vision, claude-3, gemini)
        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let visionModel = configuredProvider.models.first(where: { model in
                  model.id.contains("vision") ||
                  model.id.contains("claude-3") ||
                  model.id.contains("gemini") ||
                  model.id.contains("gpt-4o")
              }) ?? configuredProvider.models.first else {
            throw XCTSkip("No configured vision-capable AI models available")
        }

        print("   Using model: \(visionModel.name) (\(visionModel.id))")

        // Create multimodal message with a public image URL
        // Using a reliable test image (JPEG format, publicly accessible)
        let messages = [
            ChatMessage(role: .user, content: [
                .text("What do you see in this image? Describe it briefly."),
                .image(url: "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png", detail: .low)
            ])
        ]

        // Call chat completion
        let response = try await insForgeClient.ai.chatCompletion(
            model: visionModel.id,
            messages: messages,
            maxTokens: 200
        )

        // Verify response
        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        print("✅ Chat completion with image successful")
        print("   Response: \(response.content)")
        if let metadata = response.metadata {
            print("   Model used: \(metadata.model)")
        }
    }

    /// Test chat completion with PDF file input
    func testChatCompletionWithPDF() async throws {
        print("🔵 Testing chatCompletion with PDF input...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        print("   Using model: \(firstModel.name) (\(firstModel.id))")

        // Create multimodal message with a PDF URL
        // Using a reliable, publicly accessible PDF from GitHub
        let pdfUrl = "https://raw.githubusercontent.com/mozilla/pdf.js/master/web/compressed.tracemonkey-pldi-09.pdf"
        let messages = [
            ChatMessage(role: .user, content: [
                .text("What is this document about? Summarize it in one sentence."),
                .file(filename: "tracemonkey.pdf", fileData: pdfUrl)
            ])
        ]

        // Call chat completion with file parser enabled
        let response = try await insForgeClient.ai.chatCompletion(
            model: firstModel.id,
            messages: messages,
            maxTokens: 200,
            fileParser: FileParserPlugin(enabled: true, pdf: FileParserPlugin.PDFConfig(engine: .pdfText))
        )

        // Verify response
        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        print("✅ Chat completion with PDF successful")
        print("   Response: \(response.content)")
    }

    /// Test chat completion with multiple content types (text + image)
    func testChatCompletionWithMixedContent() async throws {
        print("🔵 Testing chatCompletion with mixed content...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let visionModel = configuredProvider.models.first(where: { model in
                  model.id.contains("vision") ||
                  model.id.contains("claude-3") ||
                  model.id.contains("gemini") ||
                  model.id.contains("gpt-4o")
              }) ?? configuredProvider.models.first else {
            throw XCTSkip("No configured vision-capable AI models available")
        }

        print("   Using model: \(visionModel.name) (\(visionModel.id))")

        // Conversation with multiple turns including images
        // Using a reliable test image (PNG format, publicly accessible)
        let messages = [
            ChatMessage(role: .system, content: "You are a helpful assistant that can analyze images."),
            ChatMessage(role: .user, content: [
                .text("What company logo is this?"),
                .image(url: "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png")
            ])
        ]

        let response = try await insForgeClient.ai.chatCompletion(
            model: visionModel.id,
            messages: messages,
            maxTokens: 150
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        // Response should likely mention Google
        let mentionsGoogle = response.content.lowercased().contains("google")
        print("✅ Chat completion with mixed content successful")
        print("   Response mentions Google: \(mentionsGoogle)")
        print("   Response: \(response.content)")
    }

    /// Test chat completion with base64-encoded image
    func testChatCompletionWithBase64Image() async throws {
        print("🔵 Testing chatCompletion with base64 image...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let visionModel = configuredProvider.models.first(where: { model in
                  model.id.contains("vision") ||
                  model.id.contains("claude-3") ||
                  model.id.contains("gemini") ||
                  model.id.contains("gpt-4o")
              }) ?? configuredProvider.models.first else {
            throw XCTSkip("No configured vision-capable AI models available")
        }

        print("   Using model: \(visionModel.name) (\(visionModel.id))")

        // Small 1x1 red pixel PNG as base64 (minimal test image)
        let base64Image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

        let messages = [
            ChatMessage(role: .user, content: [
                .text("What color is this tiny image? Just say the color."),
                .image(url: base64Image, detail: .low)
            ])
        ]

        let response = try await insForgeClient.ai.chatCompletion(
            model: visionModel.id,
            messages: messages,
            maxTokens: 50
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        print("✅ Chat completion with base64 image successful")
        print("   Response: \(response.content)")
    }

    /// Test chat completion with web search enabled
    func testChatCompletionWithWebSearch() async throws {
        print("🔵 Testing chatCompletion with web search...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        print("   Using model: \(firstModel.name) (\(firstModel.id))")

        let messages = [
            ChatMessage(role: .user, content: "What are the latest Swift programming language features in 2024?")
        ]

        let response = try await insForgeClient.ai.chatCompletion(
            model: firstModel.id,
            messages: messages,
            maxTokens: 300,
            webSearch: WebSearchPlugin(enabled: true, maxResults: 3)
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        print("✅ Chat completion with web search successful")
        print("   Response: \(response.content)")

        // Check if annotations are present (citations from web search)
        if let annotations = response.annotations, !annotations.isEmpty {
            print("   Citations found: \(annotations.count)")
            for annotation in annotations.prefix(3) {
                if let urlCitation = annotation.urlCitation {
                    print("   - \(urlCitation.title ?? "No title"): \(urlCitation.url)")
                }
            }
        }
    }

    /// Test chat completion with thinking mode (for supported models)
    func testChatCompletionWithThinking() async throws {
        print("🔵 Testing chatCompletion with thinking mode...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        // Look for Anthropic Claude model that supports thinking (needs :thinking suffix support)
        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let claudeModel = configuredProvider.models.first(where: { model in
                  // Look for models that explicitly support thinking mode
                  model.id.contains("claude") && model.id.contains("thinking")
              }) else {
            // If no thinking model is explicitly available, skip the test
            throw XCTSkip("No Claude model with thinking support is enabled on the server.")
        }

        print("   Using model: \(claudeModel.name) (\(claudeModel.id))")

        let messages = [
            ChatMessage(role: .user, content: "What is 15 * 17? Show your reasoning step by step.")
        ]

        let response = try await insForgeClient.ai.chatCompletion(
            model: claudeModel.id,
            messages: messages,
            maxTokens: 500,
            thinking: true
        )

        XCTAssertTrue(response.success)
        XCTAssertFalse(response.content.isEmpty)

        // Response should contain 255 (15 * 17)
        let containsAnswer = response.content.contains("255")
        print("✅ Chat completion with thinking mode successful")
        print("   Contains correct answer (255): \(containsAnswer)")
        print("   Response: \(response.content)")
    }

    // MARK: - Image Generation Tests

    /// Test image generation
    func testGenerateImage() async throws {
        print("🔵 Testing generateImage...")

        // Get available models
        let modelsResponse = try await insForgeClient.ai.listModels()

        // Find first configured image provider and model
        guard let configuredProvider = modelsResponse.image.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured image AI models available")
        }

        print("   Using model: \(firstModel.name) (\(firstModel.id))")

        // Generate image
        let prompt = "A cute Swift logo bird flying over a mountain landscape, digital art"
        let response = try await insForgeClient.ai.generateImage(
            model: firstModel.id,
            prompt: prompt
        )

        // Verify response
        XCTAssertFalse(response.images.isEmpty)
        XCTAssertGreaterThan(response.imageCount, 0)

        print("✅ Image generation successful")
        print("   Model: \(response.model ?? "unknown")")
        print("   Generated \(response.imageCount) image(s)")

        for (index, image) in response.images.enumerated() {
            print("   Image \(index + 1): \(image.url)")
        }

        if let metadata = response.metadata {
            print("   Model used: \(metadata.model)")
            if let revisedPrompt = metadata.revisedPrompt {
                print("   Revised prompt: \(revisedPrompt)")
            }
        }
    }

    /// Test image generation with simple prompt
    func testGenerateImageSimplePrompt() async throws {
        print("🔵 Testing generateImage with simple prompt...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.image.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured image AI models available")
        }

        let response = try await insForgeClient.ai.generateImage(
            model: firstModel.id,
            prompt: "A red apple"
        )

        XCTAssertFalse(response.images.isEmpty)

        // Verify each image has a valid URL
        for image in response.images {
            XCTAssertFalse(image.url.isEmpty)
            XCTAssertEqual(image.type, "imageUrl")
        }

        print("✅ Simple image generation successful")
        print("   Generated URLs are valid: \(response.images.allSatisfy { !$0.url.isEmpty })")
    }

    /// Test error handling for invalid model
    func testChatCompletionInvalidModel() async throws {
        print("🔵 Testing chatCompletion with invalid model...")

        let messages = [
            ChatMessage(role: .user, content: "Hello")
        ]

        do {
            _ = try await insForgeClient.ai.chatCompletion(
                model: "invalid-model-12345",
                messages: messages
            )
            XCTFail("Should have thrown an error for invalid model")
        } catch {
            // Expected to fail
            print("✅ Correctly threw error for invalid model: \(error)")
        }
    }

    /// Test empty messages array handling
    func testChatCompletionEmptyMessages() async throws {
        print("🔵 Testing chatCompletion with empty messages...")

        let modelsResponse = try await insForgeClient.ai.listModels()

        guard let configuredProvider = modelsResponse.text.first(where: { $0.configured }),
              let firstModel = configuredProvider.models.first else {
            throw XCTSkip("No configured text AI models available")
        }

        do {
            _ = try await insForgeClient.ai.chatCompletion(
                model: firstModel.id,
                messages: []
            )
            // May or may not fail depending on API implementation
            print("   Empty messages array was accepted")
        } catch {
            // Expected to fail
            print("✅ Correctly threw error for empty messages: \(error)")
        }
    }

    // MARK: - Embeddings Tests

    /// Test embeddings generation with single text input
    func testGenerateEmbeddingsSingleText() async throws {
        print("🔵 Testing generateEmbeddings with single text...")

        let response = try await insForgeClient.ai.generateEmbeddings(
            model: "google/gemini-embedding-001",
            input: .single("Hello world")
        )

        // Verify response structure
        XCTAssertEqual(response.object, "list")
        XCTAssertFalse(response.data.isEmpty)
        XCTAssertEqual(response.data.count, 1)

        let embedding = response.data[0]
        XCTAssertEqual(embedding.object, "embedding")
        XCTAssertEqual(embedding.index, 0)
        XCTAssertFalse(embedding.embedding.isEmpty)

        print("✅ Single text embedding successful")
        print("   Embedding dimensions: \(embedding.embedding.count)")
        if let metadata = response.metadata {
            print("   Model: \(metadata.model)")
            if let usage = metadata.usage {
                print("   Tokens: \(usage.totalTokens)")
            }
        }
    }

    /// Test embeddings generation with multiple text inputs
    func testGenerateEmbeddingsMultipleTexts() async throws {
        print("🔵 Testing generateEmbeddings with multiple texts...")

        let texts = ["Hello", "World", "Swift SDK"]
        let response = try await insForgeClient.ai.generateEmbeddings(
            model: "google/gemini-embedding-001",
            input: .multiple(texts)
        )

        // Verify response structure
        XCTAssertEqual(response.object, "list")
        XCTAssertEqual(response.data.count, texts.count)

        // Verify each embedding
        for (index, embedding) in response.data.enumerated() {
            XCTAssertEqual(embedding.object, "embedding")
            XCTAssertEqual(embedding.index, index)
            XCTAssertFalse(embedding.embedding.isEmpty)
            print("   Index \(embedding.index): \(embedding.embedding.count) dimensions")
        }

        print("✅ Multiple texts embedding successful")
        print("   Generated \(response.data.count) embeddings")
    }

    /// Test embeddings generation with encoding format parameter
    func testGenerateEmbeddingsWithEncodingFormat() async throws {
        print("🔵 Testing generateEmbeddings with encoding format...")

        let response = try await insForgeClient.ai.generateEmbeddings(
            model: "google/gemini-embedding-001",
            input: .single("Test encoding format"),
            encodingFormat: .float
        )

        XCTAssertEqual(response.object, "list")
        XCTAssertFalse(response.data.isEmpty)

        let embedding = response.data[0]
        XCTAssertFalse(embedding.embedding.isEmpty)

        print("✅ Embedding with encoding format successful")
        print("   Embedding dimensions: \(embedding.embedding.count)")
    }

    /// Test embeddings error handling for invalid model
    func testGenerateEmbeddingsInvalidModel() async throws {
        print("🔵 Testing generateEmbeddings with invalid model...")

        do {
            _ = try await insForgeClient.ai.generateEmbeddings(
                model: "invalid-embedding-model-12345",
                input: .single("Test")
            )
            XCTFail("Should have thrown an error for invalid model")
        } catch {
            print("✅ Correctly threw error for invalid model: \(error)")
        }
    }

    // MARK: - Workflow Tests

    /// Test complete AI workflow
    func testCompleteAIWorkflow() async throws {
        print("🔵 Testing complete AI workflow...")

        // 1. List available models
        let modelsResponse = try await insForgeClient.ai.listModels()
        XCTAssertFalse(modelsResponse.text.isEmpty || modelsResponse.image.isEmpty)
        print("   ✓ Listed models")

        // 2. Test chat if available
        if let textProvider = modelsResponse.text.first(where: { $0.configured }),
           let textModel = textProvider.models.first {
            let chatResponse = try await insForgeClient.ai.chatCompletion(
                model: textModel.id,
                messages: [ChatMessage(role: .user, content: "Say 'test' only.")]
            )
            XCTAssertTrue(chatResponse.success)
            print("   ✓ Chat completion successful")
        } else {
            print("   ⊘ Text AI not configured, skipping chat test")
        }

        // 3. Test image generation if available
        if let imageProvider = modelsResponse.image.first(where: { $0.configured }),
           let imageModel = imageProvider.models.first {
            let imageResponse = try await insForgeClient.ai.generateImage(
                model: imageModel.id,
                prompt: "A simple test image"
            )
            XCTAssertFalse(imageResponse.images.isEmpty)
            print("   ✓ Image generation successful")
        } else {
            print("   ⊘ Image AI not configured, skipping image test")
        }

        print("✅ Complete AI workflow successful!")
    }
}
