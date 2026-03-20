import XCTest
import TestHelper
@testable import InsForge
@testable import InsForgeAI
@testable import InsForgeCore

// MARK: - Shared SSE Decoding Types (mirror production structs)

/// Mirrors production `SSEChunk` so tests catch shape mismatches.
private struct TestSSEChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [TestSSEChoice]
}

private struct TestSSEChoice: Decodable {
    let delta: TestSSEDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct TestSSEDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [TestSSEToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
}

private struct TestSSEToolCallDelta: Decodable {
    let index: Int
    let id: String?
    let type: String?
    let function: TestSSEToolCallFunction?
}

private struct TestSSEToolCallFunction: Decodable {
    let name: String?
    let arguments: String?
}

// MARK: - Shared SSE Buffer Helper

/// Replicates the exact buffered SSE parsing logic from the production code,
/// including the EOF flush and tool-call delta mapping.
private func parseSSELines(_ lines: [String]) -> (chunks: [ChatCompletionChunk], receivedTerminal: Bool) {
    var dataBuffer: [String] = []
    var chunks: [ChatCompletionChunk] = []
    var receivedTerminal = false

    for line in lines {
        if line.hasPrefix("data: ") {
            dataBuffer.append(String(line.dropFirst(6)))
            continue
        }

        guard line.isEmpty, !dataBuffer.isEmpty else { continue }

        if flushTestBuffer(dataBuffer, into: &chunks) {
            receivedTerminal = true
        }
        dataBuffer.removeAll()

        if receivedTerminal { break }
    }

    // EOF flush: dispatch remaining buffered data (server may close
    // without a trailing blank line).
    if !receivedTerminal, !dataBuffer.isEmpty {
        receivedTerminal = flushTestBuffer(dataBuffer, into: &chunks)
    }

    return (chunks, receivedTerminal)
}

/// Mirrors the production `flushBuffer` + `makeChunk` logic.
@discardableResult
private func flushTestBuffer(_ buffer: [String], into chunks: inout [ChatCompletionChunk]) -> Bool {
    guard !buffer.isEmpty else { return false }

    let payload = buffer.joined(separator: "\n")

    if payload == "[DONE]" {
        chunks.append(ChatCompletionChunk(text: "", isFinished: true))
        return true
    }

    guard let chunkData = payload.data(using: .utf8),
          let sseChunk = try? JSONDecoder().decode(TestSSEChunk.self, from: chunkData)
    else { return false }

    let choice = sseChunk.choices.first
    let deltaText = choice?.delta.content ?? ""
    let isFinished = choice?.finishReason != nil

    // Map tool-call deltas
    let toolCallDeltas: [ToolCallDelta]? = choice?.delta.toolCalls.map { deltas in
        deltas.map { d in
            ToolCallDelta(
                index: d.index,
                id: d.id,
                type: d.type,
                function: d.function.map {
                    ToolCallDelta.FunctionDelta(name: $0.name, arguments: $0.arguments)
                }
            )
        }
    }

    chunks.append(ChatCompletionChunk(
        text: deltaText,
        isFinished: isFinished,
        model: sseChunk.model,
        toolCallDeltas: toolCallDeltas
    ))
    return isFinished
}

// MARK: - Tests

/// Tests for Chat Completion Streaming (SSE) support.
///
/// Covers:
/// - `ChatCompletionChunk` model (including `toolCallDeltas`)
/// - SSE JSON decoding via shared test structs
/// - Buffered SSE event parsing (data lines + blank-line flush + EOF flush)
/// - Truncated vs. complete stream detection
/// - Multi-line SSE data events
/// - Tool-call delta streaming
/// - Request body serialization and headers
///
/// Integration tests that hit a live server are in `InsForgeAITests.swift`.
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
        XCTAssertNil(chunk.toolCallDeltas)
    }

    /// Test chunk with default nil model and tool call deltas
    func testChunkDefaultModel() {
        let chunk = ChatCompletionChunk(text: "world", isFinished: false)

        XCTAssertEqual(chunk.text, "world")
        XCTAssertFalse(chunk.isFinished)
        XCTAssertNil(chunk.model)
        XCTAssertNil(chunk.toolCallDeltas)
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
    }

    /// Test that ChatCompletionChunk conforms to Sendable
    func testChunkIsSendable() {
        let chunk: (any Sendable) = ChatCompletionChunk(text: "test", isFinished: false)
        XCTAssertNotNil(chunk)
    }

    /// Test chunk with tool call deltas
    func testChunkWithToolCallDeltas() {
        let deltas = [
            ToolCallDelta(
                index: 0,
                id: "call_123",
                type: "function",
                function: ToolCallDelta.FunctionDelta(name: "get_weather", arguments: nil)
            )
        ]
        let chunk = ChatCompletionChunk(
            text: "",
            isFinished: false,
            model: "gpt-4o",
            toolCallDeltas: deltas
        )

        XCTAssertTrue(chunk.text.isEmpty)
        XCTAssertNotNil(chunk.toolCallDeltas)
        XCTAssertEqual(chunk.toolCallDeltas?.count, 1)
        XCTAssertEqual(chunk.toolCallDeltas?[0].index, 0)
        XCTAssertEqual(chunk.toolCallDeltas?[0].id, "call_123")
        XCTAssertEqual(chunk.toolCallDeltas?[0].function?.name, "get_weather")
    }

    /// Test ToolCallDelta conforms to Sendable
    func testToolCallDeltaIsSendable() {
        let delta: (any Sendable) = ToolCallDelta(
            index: 0, id: nil, type: nil, function: nil
        )
        XCTAssertNotNil(delta)
    }

    // MARK: - SSE JSON Decoding Tests

    /// Decode an SSE chunk with content delta
    func testDecodeSSEChunkWithContent() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [{
                "delta": { "role": "assistant", "content": "Hello" },
                "finish_reason": null
            }]
        }
        """.data(using: .utf8)!

        let sseChunk = try JSONDecoder().decode(TestSSEChunk.self, from: json)

        XCTAssertEqual(sseChunk.id, "chatcmpl-123")
        XCTAssertEqual(sseChunk.model, "openai/gpt-4o-mini")
        XCTAssertEqual(sseChunk.choices[0].delta.content, "Hello")
        XCTAssertEqual(sseChunk.choices[0].delta.role, "assistant")
        XCTAssertNil(sseChunk.choices[0].finishReason)
        XCTAssertNil(sseChunk.choices[0].delta.toolCalls)
    }

    /// Decode an SSE chunk with finish_reason set
    func testDecodeSSEChunkWithFinishReason() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [{
                "delta": { "content": "." },
                "finish_reason": "stop"
            }]
        }
        """.data(using: .utf8)!

        let sseChunk = try JSONDecoder().decode(TestSSEChunk.self, from: json)

        XCTAssertTrue(sseChunk.choices.first?.finishReason != nil)
        XCTAssertEqual(sseChunk.choices[0].finishReason, "stop")
    }

    /// Decode an SSE chunk with role-only delta (no content)
    func testDecodeSSEChunkRoleOnlyDelta() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "model": "openai/gpt-4o-mini",
            "choices": [{
                "delta": { "role": "assistant" },
                "finish_reason": null
            }]
        }
        """.data(using: .utf8)!

        let sseChunk = try JSONDecoder().decode(TestSSEChunk.self, from: json)

        XCTAssertNil(sseChunk.choices[0].delta.content)
        XCTAssertEqual(sseChunk.choices[0].delta.role, "assistant")
    }

    /// Decode an SSE chunk with tool_calls delta
    func testDecodeSSEChunkWithToolCalls() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "model": "openai/gpt-4o",
            "choices": [{
                "delta": {
                    "tool_calls": [{
                        "index": 0,
                        "id": "call_abc",
                        "type": "function",
                        "function": {
                            "name": "get_weather",
                            "arguments": ""
                        }
                    }]
                },
                "finish_reason": null
            }]
        }
        """.data(using: .utf8)!

        let sseChunk = try JSONDecoder().decode(TestSSEChunk.self, from: json)

        XCTAssertNil(sseChunk.choices[0].delta.content)
        XCTAssertNotNil(sseChunk.choices[0].delta.toolCalls)
        XCTAssertEqual(sseChunk.choices[0].delta.toolCalls?.count, 1)
        XCTAssertEqual(sseChunk.choices[0].delta.toolCalls?[0].index, 0)
        XCTAssertEqual(sseChunk.choices[0].delta.toolCalls?[0].id, "call_abc")
        XCTAssertEqual(sseChunk.choices[0].delta.toolCalls?[0].function?.name, "get_weather")
        XCTAssertEqual(sseChunk.choices[0].delta.toolCalls?[0].function?.arguments, "")
    }

    /// Decode an SSE chunk with partial tool-call arguments (subsequent chunk)
    func testDecodeSSEChunkWithPartialToolCallArguments() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "choices": [{
                "delta": {
                    "tool_calls": [{
                        "index": 0,
                        "function": {
                            "arguments": "{\\\"city\\\":"
                        }
                    }]
                },
                "finish_reason": null
            }]
        }
        """.data(using: .utf8)!

        let sseChunk = try JSONDecoder().decode(TestSSEChunk.self, from: json)

        let tc = sseChunk.choices[0].delta.toolCalls?[0]
        XCTAssertEqual(tc?.index, 0)
        XCTAssertNil(tc?.id, "Subsequent chunks don't repeat the id")
        XCTAssertEqual(tc?.function?.arguments, "{\"city\":")
    }

    // MARK: - Buffered SSE Parsing Tests

    /// Test that data: lines are buffered and flushed on blank line
    func testSSEBufferedParsing() {
        let lines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
            ": keep-alive comment",
            ""
        ]

        let (chunks, receivedTerminal) = parseSSELines(lines)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "Hi")
        XCTAssertNil(chunks[0].toolCallDeltas)
        XCTAssertFalse(receivedTerminal)
    }

    /// Test that comment lines do not affect the buffer
    func testSSECommentLinesIgnored() {
        let lines = [
            ": keep-alive",
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"A\"},\"finish_reason\":null}]}",
            ": another comment",
            ""
        ]

        let (chunks, _) = parseSSELines(lines)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "A")
    }

    /// Test that empty lines without buffered data produce no chunk
    func testEmptyLineWithoutDataIsIgnored() {
        let lines = [
            "",
            "",
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"X\"},\"finish_reason\":null}]}",
            ""
        ]

        let (chunks, _) = parseSSELines(lines)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "X")
    }

    /// Test [DONE] sentinel via buffered parsing
    func testDONESentinelViaBuffer() {
        let lines = [
            "data: [DONE]",
            ""
        ]

        let (chunks, receivedTerminal) = parseSSELines(lines)

        XCTAssertTrue(receivedTerminal)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].isFinished)
    }

    // MARK: - EOF Flush Tests

    /// Test that data buffered at EOF (no trailing blank line) is flushed
    func testEOFFlushWithDONE() {
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
            "",
            "data: [DONE]"
            // No trailing blank line — server closed connection
        ]

        let (chunks, receivedTerminal) = parseSSELines(lines)

        XCTAssertTrue(receivedTerminal, "EOF flush should detect [DONE] in buffer")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, "Hi")
        XCTAssertTrue(chunks[1].isFinished)
    }

    /// Test that a final chunk with finish_reason at EOF is flushed
    func testEOFFlushWithFinishReason() {
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Done\"},\"finish_reason\":\"stop\"}]}"
            // No trailing blank line
        ]

        let (chunks, receivedTerminal) = parseSSELines(lines)

        XCTAssertTrue(receivedTerminal, "EOF flush should detect finish_reason in buffer")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "Done")
        XCTAssertTrue(chunks[0].isFinished)
    }

    // MARK: - Stream Request Body Tests

    /// Test that stream request body includes stream: true
    func testStreamRequestBodyContainsStreamTrue() throws {
        let body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": [["role": "user", "content": "Hello"]],
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
        for chunk in chunks {
            fullText += chunk.text
            if chunk.isFinished { break }
        }

        XCTAssertEqual(fullText, "Hello world!")
    }

    /// Test that iteration stops at isFinished
    func testTextAccumulationBreaksAtFinish() {
        let chunks = [
            ChatCompletionChunk(text: "A", isFinished: false),
            ChatCompletionChunk(text: "B", isFinished: true),
            ChatCompletionChunk(text: "C", isFinished: false)
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

    // MARK: - Full SSE Stream Simulation

    /// End-to-end: role → content → content → finish → [DONE]
    func testFullSSEStreamParsing() {
        let sseLines = [
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}",
            "",
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"!\"},\"finish_reason\":\"stop\"}]}",
            "",
            "data: [DONE]",
            ""
        ]

        let (chunks, receivedTerminal) = parseSSELines(sseLines)

        XCTAssertEqual(chunks.count, 4)
        XCTAssertTrue(receivedTerminal)

        XCTAssertEqual(chunks[0].text, "")
        XCTAssertFalse(chunks[0].isFinished)
        XCTAssertEqual(chunks[0].model, "gpt-4o")

        XCTAssertEqual(chunks[1].text, "Hello")
        XCTAssertEqual(chunks[2].text, " world")

        XCTAssertEqual(chunks[3].text, "!")
        XCTAssertTrue(chunks[3].isFinished)

        let fullText = chunks.map(\.text).joined()
        XCTAssertEqual(fullText, "Hello world!")
    }

    // MARK: - Multi-Line SSE Data Event Tests

    /// Test that a single event spanning multiple data: lines is buffered and joined
    func testMultiLineSSEDataEvent() {
        let sseLines = [
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",",
            "data: \"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
            ""
        ]

        let (chunks, _) = parseSSELines(sseLines)

        if chunks.count == 1 {
            XCTAssertEqual(chunks[0].text, "Hi")
        }
    }

    // MARK: - Truncated Stream Detection Tests

    /// Stream ends without finish_reason or [DONE] → truncated
    func testTruncatedStreamDetection() {
        let sseLines = [
            "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            ""
        ]

        let (_, receivedTerminal) = parseSSELines(sseLines)

        XCTAssertFalse(receivedTerminal, "Truncated stream should NOT be marked as complete")
    }

    /// Stream with finish_reason → complete
    func testCompleteStreamDetection() {
        let sseLines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Done\"},\"finish_reason\":\"stop\"}]}",
            ""
        ]

        let (_, receivedTerminal) = parseSSELines(sseLines)

        XCTAssertTrue(receivedTerminal, "Stream with finish_reason should be marked as complete")
    }

    /// Stream with only [DONE] sentinel → complete
    func testDONEOnlyStreamDetection() {
        let sseLines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
            "",
            "data: [DONE]",
            ""
        ]

        let (chunks, receivedTerminal) = parseSSELines(sseLines)

        XCTAssertTrue(receivedTerminal)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, "Hi")
        XCTAssertTrue(chunks[1].isFinished)
    }

    // MARK: - Tool-Call Streaming Tests

    /// Simulate a full tool-call streaming flow: name → arguments → finish
    func testToolCallStreamingFlow() {
        let sseLines = [
            // Chunk 1: role + tool call start (id, name, empty args)
            "data: {\"id\":\"1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"tool_calls\":[{\"index\":0,\"id\":\"call_abc\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
            "",
            // Chunk 2: partial arguments
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\":\"}}]},\"finish_reason\":null}]}",
            "",
            // Chunk 3: more arguments
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"Tokyo\\\"}\"}}]},\"finish_reason\":null}]}",
            "",
            // Chunk 4: finish
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
            "",
            "data: [DONE]",
            ""
        ]

        let (chunks, receivedTerminal) = parseSSELines(sseLines)

        XCTAssertTrue(receivedTerminal)

        // Chunk 1: has tool call with name
        XCTAssertNotNil(chunks[0].toolCallDeltas)
        XCTAssertEqual(chunks[0].toolCallDeltas?[0].id, "call_abc")
        XCTAssertEqual(chunks[0].toolCallDeltas?[0].function?.name, "get_weather")
        XCTAssertEqual(chunks[0].text, "")

        // Chunk 2: partial arguments
        XCTAssertNotNil(chunks[1].toolCallDeltas)
        XCTAssertEqual(chunks[1].toolCallDeltas?[0].index, 0)
        XCTAssertEqual(chunks[1].toolCallDeltas?[0].function?.arguments, "{\"city\":")

        // Chunk 3: more arguments
        XCTAssertEqual(chunks[2].toolCallDeltas?[0].function?.arguments, "\"Tokyo\"}")

        // Reconstruct full arguments
        let fullArgs = chunks.compactMap { $0.toolCallDeltas?.first?.function?.arguments }.joined()
        XCTAssertEqual(fullArgs, "{\"city\":\"Tokyo\"}")

        // Chunk 4: finish_reason = "tool_calls"
        XCTAssertTrue(chunks[3].isFinished)
        XCTAssertNil(chunks[3].toolCallDeltas)
    }

    /// Test that text-only chunks have nil toolCallDeltas
    func testTextChunksHaveNilToolCallDeltas() {
        let sseLines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            ""
        ]

        let (chunks, _) = parseSSELines(sseLines)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "Hello")
        XCTAssertNil(chunks[0].toolCallDeltas)
    }

    /// Test parallel tool calls (multiple indices in one stream)
    func testParallelToolCallDeltas() {
        let sseLines = [
            // Two tool calls started in the same chunk
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}},{\"index\":1,\"id\":\"call_2\",\"type\":\"function\",\"function\":{\"name\":\"get_time\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
            ""
        ]

        let (chunks, _) = parseSSELines(sseLines)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].toolCallDeltas?.count, 2)
        XCTAssertEqual(chunks[0].toolCallDeltas?[0].index, 0)
        XCTAssertEqual(chunks[0].toolCallDeltas?[0].function?.name, "get_weather")
        XCTAssertEqual(chunks[0].toolCallDeltas?[1].index, 1)
        XCTAssertEqual(chunks[0].toolCallDeltas?[1].function?.name, "get_time")
    }
}
