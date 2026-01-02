import Foundation
import InsForgeCore
import InsForgeAuth
import Starscream

/// Realtime client for pub/sub messaging
public actor RealtimeClient {
    private let url: URL
    private let apiKey: String
    private let headersProvider: LockIsolated<[String: String]>
    private let logger: (any InsForgeLogger)?
    private var socket: WebSocket?
    private var isConnected = false
    private var subscriptions: [String: [(RealtimeMessage) -> Void]] = [:]
    private var channels: [String: RealtimeChannel] = [:]

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    public init(
        url: URL,
        apiKey: String,
        headersProvider: LockIsolated<[String: String]>,
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.apiKey = apiKey
        self.headersProvider = headersProvider
        self.logger = logger
    }

    // MARK: - High-Level Channel API

    /// Get or create a channel
    /// - Parameter channelName: Name of the channel
    /// - Returns: RealtimeChannel instance
    public func channel(_ channelName: String) -> RealtimeChannel {
        if let existing = channels[channelName] {
            return existing
        }

        let newChannel = RealtimeChannel(channelName: channelName, client: self)
        channels[channelName] = newChannel
        return newChannel
    }

    /// Remove a channel
    /// - Parameter channelName: Name of the channel to remove
    public func removeChannel(_ channelName: String) {
        channels.removeValue(forKey: channelName)
    }

    // MARK: - Connection

    /// Connect to realtime server
    public func connect() async throws {
        guard !isConnected else {
            logger?.log("Already connected to realtime server")
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()

        self.socket = socket
        logger?.log("Connecting to realtime server at \(url)")
    }

    /// Disconnect from realtime server
    public func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
        logger?.log("Disconnected from realtime server")
    }

    // MARK: - Channels

    /// Subscribe to a channel
    public func subscribe(
        to channel: String,
        onMessage: @escaping (RealtimeMessage) -> Void
    ) {
        if subscriptions[channel] == nil {
            subscriptions[channel] = []
        }
        subscriptions[channel]?.append(onMessage)

        logger?.log("Subscribed to channel: \(channel)")
    }

    /// Unsubscribe from a channel
    public func unsubscribe(from channel: String) {
        subscriptions.removeValue(forKey: channel)
        logger?.log("Unsubscribed from channel: \(channel)")
    }

    /// Publish a message to a channel
    public func publish(
        to channel: String,
        event: String,
        payload: [String: Any]
    ) async throws {
        guard isConnected else {
            throw InsForgeError.unknown("Not connected to realtime server")
        }

        let message: [String: Any] = [
            "type": "publish",
            "channel": channel,
            "event": event,
            "payload": payload
        ]

        let data = try JSONSerialization.data(withJSONObject: message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw InsForgeError.encodingError(NSError(domain: "RealtimeClient", code: -1))
        }

        socket?.write(string: jsonString)
        logger?.log("Published to channel '\(channel)': \(event)")
    }

    // MARK: - Private

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(RealtimeMessage.self, from: data)

            if let channelName = message.channelName {
                // Notify all subscribers of this channel
                subscriptions[channelName]?.forEach { callback in
                    callback(message)
                }
            }
        } catch {
            logger?.error("Failed to decode realtime message: \(error)")
        }
    }
}

// MARK: - WebSocketDelegate

extension RealtimeClient: WebSocketDelegate {
    nonisolated public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        Task {
            await handleWebSocketEvent(event)
        }
    }

    private func handleWebSocketEvent(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            isConnected = true
            logger?.log("WebSocket connected")

        case .disconnected(let reason, let code):
            isConnected = false
            logger?.log("WebSocket disconnected: \(reason) (code: \(code))")

        case .text(let text):
            handleMessage(text)

        case .error(let error):
            logger?.error("WebSocket error: \(String(describing: error))")

        case .pong, .ping, .viabilityChanged, .reconnectSuggested, .cancelled, .binary, .peerClosed:
            break
        }
    }
}

// MARK: - Models

/// Realtime message
public struct RealtimeMessage: Codable, Sendable {
    public let id: String?
    public let eventName: String?
    public let channelName: String?
    public let payload: [String: AnyCodable]?
    public let senderType: String?
    public let senderId: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, eventName, channelName, payload, senderType, senderId, createdAt
    }
}

/// Channel model
public struct Channel: Codable, Sendable {
    public let id: String
    public let pattern: String
    public let description: String?
    public let webhookUrls: [String]?
    public let enabled: Bool
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, pattern, description, webhookUrls, enabled, createdAt, updatedAt
    }
}
