import XCTest
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
    // MARK: - Configuration

    /// Your InsForge instance URL
    private let insForgeURL = "https://pg6afqz9.us-east.insforge.app"

    /// Your InsForge API key
    private let apiKey = "ik_ca177fcf1e2e72e8d1e0c2c23dbe3b79"

    // MARK: - Helper

    private var insForgeClient: InsForgeClient!

    override func setUp() async throws {
        insForgeClient = InsForgeClient(
            insForgeURL: URL(string: insForgeURL)!,
            insForgeKey: apiKey
        )
        print("📍 InsForge URL: \(insForgeURL)")
    }

    override func tearDown() async throws {
        insForgeClient = nil
    }

    // MARK: - Model Tests

    func testChatMessageCreation() {
        let message = ChatMessage(role: .user, content: "Hello, AI!")

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello, AI!")

        let dict = message.toDictionary()
        XCTAssertEqual(dict["role"], "user")
        XCTAssertEqual(dict["content"], "Hello, AI!")
    }

    func testChatMessageRoles() {
        let userMessage = ChatMessage(role: .user, content: "Question")
        let assistantMessage = ChatMessage(role: .assistant, content: "Answer")
        let systemMessage = ChatMessage(role: .system, content: "Context")

        XCTAssertEqual(userMessage.role.rawValue, "user")
        XCTAssertEqual(assistantMessage.role.rawValue, "assistant")
        XCTAssertEqual(systemMessage.role.rawValue, "system")
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
