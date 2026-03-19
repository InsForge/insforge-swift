import Foundation
import InsForgeCore

// MARK: - Public Streaming Response Type

/// A single chunk delivered by a streaming chat completion via Server-Sent Events.
///
/// Iterate chunks with `for try await chunk in stream { ... }`.
/// The stream ends either when `isFinished` is `true` or the `AsyncThrowingStream` finishes.
public struct ChatCompletionChunk: Sendable {
    /// The incremental text content for this chunk.
    /// Empty on role-only deltas and on the terminal `[DONE]` chunk.
    public let text: String

    /// `true` when the server has signalled the end of the stream
    /// (`finish_reason` is set, or `data: [DONE]` was received).
    public let isFinished: Bool

    /// The model that produced this chunk.
    /// Usually present on the first chunk only; `nil` on subsequent chunks.
    public let model: String?

    public init(text: String, isFinished: Bool, model: String? = nil) {
        self.text = text
        self.isFinished = isFinished
        self.model = model
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
                do {
                    // Allow one automatic token refresh on 401.
                    var currentHeaders = requestHeaders
                    for attempt in 0..<2 {
                        var request = URLRequest(url: endpoint)
                        request.httpMethod = "POST"
                        request.httpBody = bodyData
                        for (key, value) in currentHeaders {
                            request.setValue(value, forHTTPHeaderField: key)
                        }

                        let (bytes, urlResponse) = try await URLSession.shared.bytes(for: request)

                        guard let httpResponse = urlResponse as? HTTPURLResponse else {
                            continuation.finish(throwing: InsForgeError.invalidResponse)
                            return
                        }

                        // ── 401: refresh token and retry once ────────────────
                        if httpResponse.statusCode == 401,
                           attempt == 0,
                           let handler = refreshHandler {
                            let newToken = try await handler.refreshToken()
                            currentHeaders["Authorization"] = "Bearer \(newToken)"
                            continue
                        }

                        // ── Non-2xx: buffer the error body and throw ──────────
                        guard (200..<300).contains(httpResponse.statusCode) else {
                            var errorData = Data()
                            for try await byte in bytes {
                                errorData.append(byte)
                            }
                            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: errorData)
                            continuation.finish(throwing: InsForgeError.httpError(
                                statusCode: httpResponse.statusCode,
                                message: errorBody?.message ?? "Stream request failed",
                                error: errorBody?.error,
                                nextActions: errorBody?.nextActions
                            ))
                            return
                        }

                        // ── Parse SSE events ─────────────────────────────────
                        for try await line in bytes.lines {
                            // SSE spec: data lines begin with "data: "
                            guard line.hasPrefix("data: ") else { continue }
                            let payload = String(line.dropFirst(6))

                            // End-of-stream sentinel
                            if payload == "[DONE]" {
                                continuation.yield(ChatCompletionChunk(text: "", isFinished: true))
                                break
                            }

                            // Decode the JSON chunk; skip any lines that don't parse.
                            guard let chunkData = payload.data(using: .utf8),
                                  let sseChunk = try? JSONDecoder().decode(SSEChunk.self, from: chunkData)
                            else { continue }

                            let deltaText = sseChunk.choices.first?.delta.content ?? ""
                            let isFinished = sseChunk.choices.first?.finishReason != nil

                            continuation.yield(ChatCompletionChunk(
                                text: deltaText,
                                isFinished: isFinished,
                                model: sseChunk.model
                            ))

                            if isFinished { break }
                        }

                        continuation.finish()
                        return
                    }

                    // Exhausted retries (both attempts returned 401).
                    continuation.finish(throwing: InsForgeError.authenticationRequired)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
#endif
