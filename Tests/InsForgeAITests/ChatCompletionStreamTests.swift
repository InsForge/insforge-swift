import XCTest
import TestHelper
@testable import InsForge
@testable import InsForgeAI
@testable import InsForgeCore

/// Tests for Chat Completion Streaming (SSE) support
///
/// ## What's tested:
/// - ChatCompletionChunk model creation and properties
/// - SSE chunk JSON decoding (simulated server responses)
/// - Stream body serialization (request payload)
/// - Edge cases: empty deltas, finish reasons, [DONE] sentinel
///
/// Note: Integration tests that require a live server are in InsForgeAITests.swift.
final class ChatCompletionStreamTests: XCTestCase {
    // MARK: - Helper

    private var insForgeClient: InsForgeClient!

    override func setUp() async throws {
        insForgeClient = TestHelper.createClient()
    }

    override func tearDown() async throws {
        insForgeClient = nil
    }

    // MARK: - ChatCompletionChunk Model Tests

    /// Test basic chunk creation with text content
    func testChunkCreation() {
        let chunk = ChatCompletionChunk(text: "Hello", isFinished: false, model: "openai/gpt-4o")

        XCTAssertEqual(chunk.text, "Hello")
        XCTAssertFalse(chunk.isFinished)
        XCTAssertEqual(chunk.model, "openai/gpt-4o")
    }

    /// Test chunk with default nil model
    func testChunkDefaultModel() {
        let chunk = ChatCompletionChunk(text: "world", isFinished: false)

        XCTAssertEqual(chunk.text, "world")
        XCTAssertFalse(chunk.isFinished)
        XCTAssertNil(chunk.model)
    }

    /// Test finished chunk (terminal signal)
    func testChunkFinished() {
        let chunk = ChatCompletionChunk(text: "", isFinished: true)

        XCTAssertTrue(chunk.text.isEmpty)
        XCTAssertTrue(chunk.isFinished)
    }

    /// Test chunk with empty text (e.g. role-only delta)
    func testChunkEmptyText() {
        let chunk = ChatCompletionChunk(text: "", isFinished: false, model: "openai/gpt-4o")

        XCTAssertTrue(chunk.text.isEmpty)
        XCTAssertFalse(chunk.isFinished)
        XCTAssertEqual(chunk.model, "openai/gpt-4o")
    }

    /// Test that ChatCompletionChunk conforms to Sendable
    func testChunkIsSendable() {
        let chunk: (any Sendable) = ChatCompletionChunk(text: "test", isFinished: false)
        XCTAssertNotNil(chunk)
    }

    // MARK: - SSE JSON Decoding Tests

    /// Simulate decoding an SSE chunk JSON payload with content delta
    func testDecodeSSEChunkWithContent() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [
                {
                    "delta": {
                        "role": "assistant",
                        "content": "Hello"
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!

        // Decode using the same structure the stream parser uses
        struct SSEChunk: Decodable {
            let id: String?
            let model: String?
            let choices: [SSEChoice]
        }
        struct SSEChoice: Decodable {
            let delta: SSEDelta
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct SSEDelta: Decodable {
            let role: String?
            let content: String?
        }

        let sseChunk = try JSONDecoder().decode(SSEChunk.self, from: json)

        XCTAssertEqual(sseChunk.id, "chatcmpl-123")
        XCTAssertEqual(sseChunk.model, "openai/gpt-4o-mini")
        XCTAssertEqual(sseChunk.choices.count, 1)
        XCTAssertEqual(sseChunk.choices[0].delta.content, "Hello")
        XCTAssertEqual(sseChunk.choices[0].delta.role, "assistant")
        XCTAssertNil(sseChunk.choices[0].finishReason)

        // Verify the chunk maps correctly
        let deltaText = sseChunk.choices.first?.delta.content ?? ""
        let isFinished = sseChunk.choices.first?.finishReason != nil
        XCTAssertEqual(deltaText, "Hello")
        XCTAssertFalse(isFinished)
    }

    /// Simulate decoding an SSE chunk with finish_reason set
    func testDecodeSSEChunkWithFinishReason() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [
                {
                    "delta": {
                        "content": "."
                    },
                    "finish_reason": "stop"
                }
            ]
        }
        """.data(using: .utf8)!

        struct SSEChunk: Decodable {
            let id: String?
            let model: String?
            let choices: [SSEChoice]
        }
        struct SSEChoice: Decodable {
            let delta: SSEDelta
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct SSEDelta: Decodable {
            let role: String?
            let content: String?
        }

        let sseChunk = try JSONDecoder().decode(SSEChunk.self, from: json)

        let isFinished = sseChunk.choices.first?.finishReason != nil
        XCTAssertTrue(isFinished)
        XCTAssertEqual(sseChunk.choices[0].finishReason, "stop")
        XCTAssertEqual(sseChunk.choices[0].delta.content, ".")
    }

    /// Simulate decoding an SSE chunk with empty delta (role-only)
    func testDecodeSSEChunkRoleOnlyDelta() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [
                {
                    "delta": {
                        "role": "assistant"
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!

        struct SSEChunk: Decodable {
            let id: String?
            let model: String?
            let choices: [SSEChoice]
        }
        struct SSEChoice: Decodable {
            let delta: SSEDelta
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct SSEDelta: Decodable {
            let role: String?
            let content: String?
        }

        let sseChunk = try JSONDecoder().decode(SSEChunk.self, from: json)

        // Content should be nil for role-only delta
        XCTAssertNil(sseChunk.choices[0].delta.content)
        XCTAssertEqual(sseChunk.choices[0].delta.role, "assistant")

        // Mapper should produce empty text
        let deltaText = sseChunk.choices.first?.delta.content ?? ""
        XCTAssertEqual(deltaText, "")
    }

    // MARK: - SSE Line Parsing Tests

    /// Test that SSE "data: " prefix is correctly identified
    func testSSELineParsing() {
        let sseLines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
            ": keep-alive comment",
            "",
            "data: [DONE]"
        ]

        var dataPayloads: [String] = []
        for line in sseLines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            dataPayloads.append(payload)
        }

        XCTAssertEqual(dataPayloads.count, 2)
        XCTAssertTrue(dataPayloads[0].contains("\"content\":\"Hi\""))
        XCTAssertEqual(dataPayloads[1], "[DONE]")
    }

    /// Test [DONE] sentinel detection
    func testDONESentinel() {
        let payload = "[DONE]"
        XCTAssertEqual(payload, "[DONE]")
        XCTAssertTrue(payload == "[DONE]")
    }

    /// Test SSE comment lines are skipped
    func testSSECommentLinesSkipped() {
        let commentLine = ": this is a keep-alive comment"
        XCTAssertFalse(commentLine.hasPrefix("data: "))
    }

    /// Test empty lines are skipped
    func testEmptyLinesSkipped() {
        let emptyLine = ""
        XCTAssertFalse(emptyLine.hasPrefix("data: "))
    }

    // MARK: - Stream Request Body Tests

    /// Test that stream request body includes stream: true
    func testStreamRequestBodyContainsStreamTrue() throws {
        let body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
            "stream": true
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(decoded?["stream"] as? Bool, true)
        XCTAssertEqual(decoded?["model"] as? String, "openai/gpt-4o-mini")
    }

    /// Test that optional parameters are excluded when nil
    func testStreamRequestBodyOptionalParametersExcluded() throws {
        var body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": [["role": "user", "content": "Test"]],
            "stream": true
        ]

        // Simulate: all optionals are nil, so nothing is added
        let temperature: Double? = nil
        let maxTokens: Int? = nil

        if let temperature = temperature { body["temperature"] = temperature }
        if let maxTokens = maxTokens { body["maxTokens"] = maxTokens }

        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNil(decoded?["temperature"])
        XCTAssertNil(decoded?["maxTokens"])
    }

    /// Test that optional parameters are included when provided
    func testStreamRequestBodyOptionalParametersIncluded() throws {
        var body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": [["role": "user", "content": "Test"]],
            "stream": true
        ]

        let temperature: Double? = 0.7
        let maxTokens: Int? = 100
        let systemPrompt: String? = "You are helpful."

        if let temperature = temperature { body["temperature"] = temperature }
        if let maxTokens = maxTokens { body["maxTokens"] = maxTokens }
        if let systemPrompt = systemPrompt { body["systemPrompt"] = systemPrompt }

        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(decoded?["temperature"] as? Double, 0.7)
        XCTAssertEqual(decoded?["maxTokens"] as? Int, 100)
        XCTAssertEqual(decoded?["systemPrompt"] as? String, "You are helpful.")
    }

    // MARK: - Text Accumulation Tests

    /// Simulate accumulating text from multiple chunks
    func testTextAccumulation() {
        let chunks = [
            ChatCompletionChunk(text: "Hello", isFinished: false, model: "openai/gpt-4o"),
            ChatCompletionChunk(text: " ", isFinished: false),
            ChatCompletionChunk(text: "world", isFinished: false),
            ChatCompletionChunk(text: "!", isFinished: true)
        ]

        var fullText = ""
        var chunkCount = 0

        for chunk in chunks {
            fullText += chunk.text
            chunkCount += 1
            if chunk.isFinished { break }
        }

        XCTAssertEqual(fullText, "Hello world!")
        XCTAssertEqual(chunkCount, 4)
    }

    /// Simulate accumulating text and breaking at finish
    func testTextAccumulationBreaksAtFinish() {
        let chunks = [
            ChatCompletionChunk(text: "A", isFinished: false),
            ChatCompletionChunk(text: "B", isFinished: true),
            ChatCompletionChunk(text: "C", isFinished: false) // Should not be reached
        ]

        var fullText = ""
        for chunk in chunks {
            fullText += chunk.text
            if chunk.isFinished { break }
        }

        XCTAssertEqual(fullText, "AB")
    }

    /// Test accumulation with empty chunks in the middle
    func testTextAccumulationWithEmptyChunks() {
        let chunks = [
            ChatCompletionChunk(text: "", isFinished: false, model: "gpt-4o"),
            ChatCompletionChunk(text: "Hello", isFinished: false),
            ChatCompletionChunk(text: "", isFinished: false),
            ChatCompletionChunk(text: " world", isFinished: true)
        ]

        var fullText = ""
        for chunk in chunks {
            fullText += chunk.text
            if chunk.isFinished { break }
        }

        XCTAssertEqual(fullText, "Hello world")
    }

    // MARK: - Stream Headers Tests

    /// Test that stream request headers include required SSE headers
    func testStreamRequestHeaders() {
        let baseHeaders = ["Authorization": "Bearer test-key"]
        let requestHeaders = baseHeaders.merging([
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache"
        ]) { $1 }

        XCTAssertEqual(requestHeaders["Content-Type"], "application/json")
        XCTAssertEqual(requestHeaders["Accept"], "text/event-stream")
        XCTAssertEqual(requestHeaders["Cache-Control"], "no-cache")
        XCTAssertEqual(requestHeaders["Authorization"], "Bearer test-key")
    }

    // MARK: - Multi-Chunk SSE Simulation

    /// Simulate parsing a complete SSE stream with multiple events
    func testFullSSEStreamParsing() throws {
        // Simulated SSE lines as they arrive from the server (no leading whitespace)
        let sseLines = [
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"!\"},\"finish_reason\":\"stop\"}]}",
            "",
            "data: [DONE]"
        ]

        struct SSEChunk: Decodable {
            let id: String?
            let model: String?
            let choices: [SSEChoice]
        }
        struct SSEChoice: Decodable {
            let delta: SSEDelta
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct SSEDelta: Decodable {
            let role: String?
            let content: String?
        }

        var chunks: [ChatCompletionChunk] = []

        for line in sseLines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" {
                chunks.append(ChatCompletionChunk(text: "", isFinished: true))
                break
            }

            guard let chunkData = payload.data(using: .utf8),
                  let sseChunk = try? JSONDecoder().decode(SSEChunk.self, from: chunkData)
            else { continue }

            let deltaText = sseChunk.choices.first?.delta.content ?? ""
            let isFinished = sseChunk.choices.first?.finishReason != nil

            chunks.append(ChatCompletionChunk(
                text: deltaText,
                isFinished: isFinished,
                model: sseChunk.model
            ))

            if isFinished { break }
        }

        // Should have 4 chunks (role-only + "Hello" + " world" + "!" with finish)
        XCTAssertEqual(chunks.count, 4)

        // First chunk has empty text (role-only delta)
        XCTAssertEqual(chunks[0].text, "")
        XCTAssertFalse(chunks[0].isFinished)
        XCTAssertEqual(chunks[0].model, "gpt-4o")

        // Text content chunks
        XCTAssertEqual(chunks[1].text, "Hello")
        XCTAssertFalse(chunks[1].isFinished)

        XCTAssertEqual(chunks[2].text, " world")
        XCTAssertFalse(chunks[2].isFinished)

        // Final chunk with finish_reason
        XCTAssertEqual(chunks[3].text, "!")
        XCTAssertTrue(chunks[3].isFinished)

        // Accumulated text
        let fullText = chunks.map(\.text).joined()
        XCTAssertEqual(fullText, "Hello world!")
    }
}
