import Foundation
import InsForgeCore

// MARK: - Public Streaming Response Types

/// An incremental tool-call delta streamed by the model.
///
/// Arguments arrive across multiple chunks; callers should concatenate
/// `function.arguments` across all chunks that share the same `index`.
public struct ToolCallDelta: Sendable {
    /// Position of this tool call in the list (used to correlate partial chunks).
    public let index: Int
    /// Tool-call ID, present only on the first chunk for each index.
    public let id: String?
    /// Always `"function"` when present.
    public let type: String?
    /// Partial function name and/or arguments for this chunk.
    public let function: FunctionDelta?

    public struct FunctionDelta: Sendable {
        /// Function name — present only on the first chunk for each index.
        public let name: String?
        /// Partial JSON arguments string; concatenate across chunks to build the full value.
        public let arguments: String?
    }
}

/// A single chunk delivered by a streaming chat completion via Server-Sent Events.
///
/// Iterate chunks with `for try await chunk in stream { ... }`.
/// The stream ends either when `isFinished` is `true` or the `AsyncThrowingStream` finishes.
public struct ChatCompletionChunk: Sendable {
    /// The incremental text content for this chunk.
    /// Empty on role-only deltas, tool-call deltas, and the terminal `[DONE]` chunk.
    public let text: String

    /// `true` when the server has signalled the end of the stream
    /// (`finish_reason` is set, or `data: [DONE]` was received).
    public let isFinished: Bool

    /// The model that produced this chunk.
    /// Usually present on the first chunk only; `nil` on subsequent chunks.
    public let model: String?

    /// Partial tool-call deltas for this chunk.
    /// Non-nil (and non-empty) when the model is streaming a function call
    /// instead of plain text. Concatenate `function.arguments` across chunks
    /// that share the same `index` to reconstruct each full tool call.
    public let toolCallDeltas: [ToolCallDelta]?

    public init(
        text: String,
        isFinished: Bool,
        model: String? = nil,
        toolCallDeltas: [ToolCallDelta]? = nil
    ) {
        self.text = text
        self.isFinished = isFinished
        self.model = model
        self.toolCallDeltas = toolCallDeltas
    }
}

// MARK: - Private SSE Decoding Models

private struct SSEChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [SSEChoice]
}

private struct SSEChoice: Decodable {
    let delta: SSEDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct SSEDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [SSEToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
}

private struct SSEToolCallDelta: Decodable {
    let index: Int
    let id: String?
    let type: String?
    let function: SSEToolCallFunction?
}

private struct SSEToolCallFunction: Decodable {
    let name: String?
    let arguments: String?
}

// MARK: - Private SSE Event Processing

/// Converts a decoded ``SSEChunk`` into a ``ChatCompletionChunk``.
private func makeChunk(from sseChunk: SSEChunk) -> ChatCompletionChunk {
    let choice = sseChunk.choices.first
    let deltaText = choice?.delta.content ?? ""
    let isFinished = choice?.finishReason != nil

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

    return ChatCompletionChunk(
        text: deltaText,
        isFinished: isFinished,
        model: sseChunk.model,
        toolCallDeltas: toolCallDeltas
    )
}

/// Flushes `dataBuffer` as a single SSE event and yields the result into `continuation`.
/// Returns `true` if a terminal signal was encountered.
private func flushBuffer(
    _ dataBuffer: [String],
    into continuation: AsyncThrowingStream<ChatCompletionChunk, Error>.Continuation
) -> Bool {
    guard !dataBuffer.isEmpty else { return false }

    let payload = dataBuffer.joined(separator: "\n")

    if payload == "[DONE]" {
        continuation.yield(ChatCompletionChunk(text: "", isFinished: true))
        return true
    }

    guard let chunkData = payload.data(using: .utf8),
          let sseChunk = try? JSONDecoder().decode(SSEChunk.self, from: chunkData)
    else { return false }

    let chunk = makeChunk(from: sseChunk)
    continuation.yield(chunk)
    return chunk.isFinished
}

// MARK: - AIClient Streaming Extension

#if !canImport(FoundationNetworking)
extension AIClient {

    /// Stream a chat completion token-by-token via Server-Sent Events (SSE).
    ///
    /// Use this method to display text to the user as it arrives, rather than
    /// waiting for the entire response. The returned stream yields
    /// ``ChatCompletionChunk`` values until the server closes the connection.
    ///
    /// When the model invokes a tool, chunks carry ``ChatCompletionChunk/toolCallDeltas``
    /// instead of ``ChatCompletionChunk/text``. Concatenate `function.arguments` across
    /// all chunks sharing the same `index` to reconstruct each full tool call.
    ///
    /// ```swift
    /// let stream = await client.ai.chatCompletionStream(
    ///     model: "openai/gpt-4o-mini",
    ///     messages: [ChatMessage(role: .user, content: "Tell me a joke")]
    /// )
    ///
    /// var fullText = ""
    /// for try await chunk in stream {
    ///     fullText += chunk.text
    ///     print(chunk.text, terminator: "")
    ///     if chunk.isFinished { break }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. `"openai/gpt-4o-mini"`).
    ///   - messages: Conversation history.
    ///   - temperature: Sampling temperature (0–2). `nil` uses the server default.
    ///   - maxTokens: Maximum tokens to generate. `nil` uses the server default.
    ///   - topP: Nucleus sampling parameter (0–1). `nil` uses the server default.
    ///   - systemPrompt: Optional system-level instruction.
    ///   - webSearch: Web-search plugin configuration.
    ///   - fileParser: File-parser plugin configuration.
    ///   - thinking: Enable extended reasoning (Anthropic models only).
    ///   - tools: Tool definitions for function calling.
    ///   - toolChoice: Controls which tool the model may call.
    ///   - parallelToolCalls: Allow the model to call multiple tools in parallel.
    /// - Returns: An `AsyncThrowingStream` that yields ``ChatCompletionChunk`` values.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public func chatCompletionStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        systemPrompt: String? = nil,
        webSearch: WebSearchPlugin? = nil,
        fileParser: FileParserPlugin? = nil,
        thinking: Bool? = nil,
        tools: [Tool]? = nil,
        toolChoice: ToolChoice? = nil,
        parallelToolCalls: Bool? = nil
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        // ── Capture all actor-isolated state as Sendable values ──────────────
        let endpoint = url.appendingPathComponent("chat/completion")
        let requestHeaders = currentHeaders.merging([
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache"
        ]) { $1 }

        // Build the JSON body while still on the actor.
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.toDictionary() },
            "stream": true
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["maxTokens"] = maxTokens }
        if let topP { body["topP"] = topP }
        if let systemPrompt { body["systemPrompt"] = systemPrompt }
        if let webSearch { body["webSearch"] = webSearch.toDictionary() }
        if let fileParser { body["fileParser"] = fileParser.toDictionary() }
        if let thinking { body["thinking"] = thinking }
        if let tools { body["tools"] = tools.map { $0.toDictionary() } }
        if let toolChoice { body["toolChoice"] = toolChoice.toValue() }
        if let parallelToolCalls { body["parallelToolCalls"] = parallelToolCalls }

        // Serialize to Data (Sendable) before crossing actor boundary.
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InsForgeError.encodingError(
                    NSError(
                        domain: "InsForgeAI",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to serialize SSE request body"]
                    )
                ))
            }
        }

        // Capture the token-refresh handler for 401 handling.
        let refreshHandler = tokenRefreshHandler

        logger.debug("POST (stream) \(endpoint.absoluteString)")

        // ── Create the async stream ──────────────────────────────────────────
        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.performStreamTask(
                    endpoint: endpoint,
                    bodyData: bodyData,
                    requestHeaders: requestHeaders,
                    refreshHandler: refreshHandler,
                    continuation: continuation
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Executes the SSE request loop, including one 401 token-refresh retry.
    ///
    /// Extracted from `chatCompletionStream` to satisfy SwiftLint's
    /// `function_body_length` limit on the public API surface.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    private func performStreamTask(
        endpoint: URL,
        bodyData: Data,
        requestHeaders: [String: String],
        refreshHandler: (any TokenRefreshHandler)?,
        continuation: AsyncThrowingStream<ChatCompletionChunk, Error>.Continuation
    ) async {
        do {
            var currentHeaders = requestHeaders
            for attempt in 0..<2 {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.httpBody = bodyData
                for (key, value) in currentHeaders { request.setValue(value, forHTTPHeaderField: key) }

                let (bytes, urlResponse) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    continuation.finish(throwing: InsForgeError.invalidResponse); return
                }

                // ── 401: refresh token and retry once ────────────────────────
                if httpResponse.statusCode == 401, attempt == 0, let handler = refreshHandler {
                    let newToken = try await handler.refreshToken()
                    currentHeaders["Authorization"] = "Bearer \(newToken)"
                    continue
                }

                // ── Non-2xx: buffer the error body and throw ──────────────────
                guard (200..<300).contains(httpResponse.statusCode) else {
                    var errorData = Data()
                    for try await byte in bytes { errorData.append(byte) }
                    let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: errorData)
                    continuation.finish(throwing: InsForgeError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: errorBody?.message ?? "Stream request failed",
                        error: errorBody?.error,
                        nextActions: errorBody?.nextActions
                    ))
                    return
                }

                // ── Parse SSE events ──────────────────────────────────────────
                // SSE spec: an event spans one or more "data:" lines, terminated
                // by a blank line. Buffer lines until a blank line (or EOF) flushes.
                var dataBuffer: [String] = []
                var receivedTerminal = false
                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        dataBuffer.append(String(line.dropFirst(6))); continue
                    }
                    guard line.isEmpty, !dataBuffer.isEmpty else { continue }
                    if flushBuffer(dataBuffer, into: continuation) { receivedTerminal = true }
                    dataBuffer.removeAll()
                    if receivedTerminal { break }
                }

                // ── EOF flush ─────────────────────────────────────────────────
                // Some servers omit the trailing blank line after the last event.
                if !receivedTerminal, !dataBuffer.isEmpty {
                    receivedTerminal = flushBuffer(dataBuffer, into: continuation)
                }

                if receivedTerminal {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: InsForgeError.networkError(
                        .other("Stream ended without a terminal signal; response may be truncated")
                    ))
                }
                return
            }
            continuation.finish(throwing: InsForgeError.authenticationRequired)
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

#endif
