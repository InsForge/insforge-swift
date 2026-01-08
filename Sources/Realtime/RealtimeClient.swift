import Foundation
import InsForgeCore
import InsForgeAuth
import SocketIO

// MARK: - Connection State

/// Realtime connection state
public enum ConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
}

// MARK: - Subscribe Response

/// Response from subscribe operations
public enum SubscribeResponse: Sendable {
    case success(channel: String)
    case failure(channel: String, code: String, message: String)

    public var ok: Bool {
        if case .success = self { return true }
        return false
    }

    public var channel: String {
        switch self {
        case .success(let channel): return channel
        case .failure(let channel, _, _): return channel
        }
    }
}

// MARK: - Realtime Error Payload

/// Error payload from server
public struct RealtimeErrorPayload: Codable, Sendable {
    public let channel: String?
    public let code: String
    public let message: String
}

// MARK: - Socket Message

/// Meta information included in all socket messages
public struct SocketMessageMeta: Codable, Sendable {
    public let channel: String?
    public let messageId: String
    public let senderType: String
    public let senderId: String?
    public let timestamp: String
}

/// Socket message received from server
public struct SocketMessage: Sendable {
    public let meta: SocketMessageMeta
    public let payload: [String: Any]

    /// Decode payload to a specific type
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Event Callback

/// Type-erased callback wrapper for thread safety
private final class CallbackWrapper<T>: @unchecked Sendable {
    let callback: (T) -> Void
    init(_ callback: @escaping (T) -> Void) {
        self.callback = callback
    }
}

// MARK: - Realtime Client

/// Realtime client for subscribing to channels and handling real-time events via Socket.IO
///
/// Example usage:
/// ```swift
/// let realtime = client.realtime
///
/// // Connect to the realtime server
/// try await realtime.connect()
///
/// // Subscribe to a channel
/// let response = await realtime.subscribe("orders:123")
/// if !response.ok {
///     print("Failed to subscribe")
/// }
///
/// // Listen for specific events
/// realtime.on("order_updated") { (message: SocketMessage) in
///     print("Order updated:", message.payload)
/// }
///
/// // Listen for connection events
/// realtime.onConnect { print("Connected!") }
/// realtime.onDisconnect { reason in print("Disconnected:", reason) }
/// realtime.onError { error in print("Error:", error) }
///
/// // Publish a message to a channel
/// try realtime.publish(to: "orders:123", event: "status_changed", payload: ["status": "shipped"])
///
/// // Unsubscribe and disconnect when done
/// realtime.unsubscribe(from: "orders:123")
/// realtime.disconnect()
/// ```
public final class RealtimeClient: @unchecked Sendable {
    // MARK: - Properties

    private let url: URL
    private let apiKey: String
    private let headersProvider: LockIsolated<[String: String]>
    private let logger: (any InsForgeLogger)?

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let subscribedChannels = LockIsolated<Set<String>>(Set())
    private let eventListeners = LockIsolated<[String: [UUID: CallbackWrapper<SocketMessage>]]>([:])

    // Connection state callbacks
    private let connectCallbacks = LockIsolated<[UUID: CallbackWrapper<Void>]>([:])
    private let disconnectCallbacks = LockIsolated<[UUID: CallbackWrapper<String>]>([:])
    private let errorCallbacks = LockIsolated<[UUID: CallbackWrapper<RealtimeErrorPayload>]>([:])
    private let connectErrorCallbacks = LockIsolated<[UUID: CallbackWrapper<Error>]>([:])

    // MARK: - Initialization

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

    // MARK: - Connection State

    /// Check if connected to the realtime server
    public var isConnected: Bool {
        socket?.status == .connected
    }

    /// Get the current connection state
    public var connectionState: ConnectionState {
        guard let socket = socket else { return .disconnected }
        switch socket.status {
        case .connected: return .connected
        case .connecting: return .connecting
        default: return .disconnected
        }
    }

    /// Get the socket ID (if connected)
    public var socketId: String? {
        socket?.sid
    }

    // MARK: - Connection

    /// Connect to the realtime server
    public func connect() async throws {
        // Already connected
        if socket?.status == .connected {
            return
        }

        // Get current auth token
        let headers = headersProvider.value
        let authToken = headers["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? apiKey

        // Create Socket.IO manager with WebSocket transport
        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .connectParams(["token": authToken])
        ]

        manager = SocketManager(socketURL: url, config: config)
        socket = manager?.defaultSocket

        guard let socket = socket else {
            throw InsForgeError.unknown("Failed to create socket")
        }

        // Set up event handlers
        setupEventHandlers(socket)

        // Connect and wait for result
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            var resumed = false

            socket.on(clientEvent: .connect) { [weak self] _, _ in
                guard !resumed else { return }
                resumed = true
                self?.logger?.log("Connected to realtime server")

                // Re-subscribe to channels on connect/reconnect
                self?.resubscribeToChannels()
                self?.notifyConnect()

                continuation.resume()
            }

            socket.on(clientEvent: .error) { [weak self] data, _ in
                guard !resumed else { return }
                resumed = true
                let errorMessage = (data.first as? String) ?? "Unknown connection error"
                let error = NSError(domain: "RealtimeClient", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage])
                self?.logger?.error("Connection error: \(errorMessage)")
                continuation.resume(throwing: error)
            }

            socket.connect()
            self?.logger?.log("Connecting to realtime server at \(self?.url.absoluteString ?? "")")
        }
    }

    /// Disconnect from the realtime server
    public func disconnect() {
        socket?.disconnect()
        socket = nil
        manager = nil
        subscribedChannels.setValue(Set())
        logger?.log("Disconnected from realtime server")
    }

    // MARK: - Event Handlers Setup

    private func setupEventHandlers(_ socket: SocketIOClient) {
        // Handle disconnect
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            let reason = (data.first as? String) ?? "unknown"
            self?.logger?.log("Disconnected from realtime server: \(reason)")
            self?.notifyDisconnect(reason)
        }

        // Handle realtime errors
        socket.on("realtime:error") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let code = dict["code"] as? String,
                  let message = dict["message"] as? String else { return }

            let error = RealtimeErrorPayload(
                channel: dict["channel"] as? String,
                code: code,
                message: message
            )
            self?.logger?.error("Realtime error: \(code) - \(message)")
            self?.notifyError(error)
        }

        // Handle all other events (custom events from server)
        socket.onAny { [weak self] event in
            // Skip system events
            guard !event.event.starts(with: "realtime:"),
                  event.event != "connect",
                  event.event != "disconnect",
                  event.event != "error" else { return }

            self?.handleCustomEvent(event.event, data: event.items ?? [])
        }
    }

    // MARK: - Subscribe / Unsubscribe

    /// Subscribe to a channel
    /// Automatically connects if not already connected.
    /// - Parameter channel: Channel name (e.g., "orders:123", "broadcast")
    /// - Returns: Subscribe response
    public func subscribe(_ channel: String) async -> SubscribeResponse {
        // Already subscribed
        if subscribedChannels.value.contains(channel) {
            return .success(channel: channel)
        }

        // Auto-connect if not connected
        if socket?.status != .connected {
            do {
                try await connect()
            } catch {
                return .failure(channel: channel, code: "CONNECTION_FAILED", message: error.localizedDescription)
            }
        }

        guard let socket = socket else {
            return .failure(channel: channel, code: "NO_SOCKET", message: "Socket not initialized")
        }

        // Emit subscribe event and wait for acknowledgment
        return await withCheckedContinuation { [weak self] continuation in
            socket.emitWithAck("realtime:subscribe", ["channel": channel]).timingOut(after: 10) { [weak self] data in
                // Handle timeout (data will be ["NO ACK"])
                if let first = data.first as? String, first == "NO ACK" {
                    continuation.resume(returning: .failure(channel: channel, code: "TIMEOUT", message: "Subscribe request timed out"))
                    return
                }

                guard let response = data.first as? [String: Any] else {
                    continuation.resume(returning: .failure(channel: channel, code: "INVALID_RESPONSE", message: "Invalid response from server"))
                    return
                }

                if let ok = response["ok"] as? Bool, ok {
                    self?.subscribedChannels.withValue { $0.insert(channel) }
                    self?.logger?.log("Subscribed to channel: \(channel)")
                    continuation.resume(returning: .success(channel: channel))
                } else if let error = response["error"] as? [String: Any],
                          let code = error["code"] as? String,
                          let message = error["message"] as? String {
                    continuation.resume(returning: .failure(channel: channel, code: code, message: message))
                } else {
                    continuation.resume(returning: .failure(channel: channel, code: "UNKNOWN", message: "Unknown error"))
                }
            }
        }
    }

    /// Unsubscribe from a channel (fire-and-forget)
    /// - Parameter channel: Channel name to unsubscribe from
    public func unsubscribe(from channel: String) {
        subscribedChannels.withValue { $0.remove(channel) }

        if socket?.status == .connected {
            socket?.emit("realtime:unsubscribe", ["channel": channel])
            logger?.log("Unsubscribed from channel: \(channel)")
        }
    }

    // MARK: - Publish

    /// Publish a message to a channel
    /// - Parameters:
    ///   - channel: Channel name
    ///   - event: Event name
    ///   - payload: Message payload
    public func publish(to channel: String, event: String, payload: [String: Any]) throws {
        guard socket?.status == .connected else {
            throw InsForgeError.unknown("Not connected to realtime server. Call connect() first.")
        }

        socket?.emit("realtime:publish", [
            "channel": channel,
            "event": event,
            "payload": payload
        ])

        logger?.log("Published to channel '\(channel)': \(event)")
    }

    /// Publish a message with Encodable payload
    public func publish<T: Encodable>(to channel: String, event: String, payload: T) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try publish(to: channel, event: event, payload: dict)
    }

    // MARK: - Event Listeners

    /// Listen for events
    /// - Parameters:
    ///   - event: Event name to listen for
    ///   - callback: Callback when event is received
    /// - Returns: Listener ID for removal
    @discardableResult
    public func on(_ event: String, callback: @escaping (SocketMessage) -> Void) -> UUID {
        let id = UUID()
        let wrapper = CallbackWrapper(callback)
        eventListeners.withValue { listeners in
            if listeners[event] == nil {
                listeners[event] = [:]
            }
            listeners[event]?[id] = wrapper
        }
        return id
    }

    /// Remove a listener
    public func off(_ event: String, id: UUID) {
        eventListeners.withValue { listeners in
            listeners[event]?.removeValue(forKey: id)
            if listeners[event]?.isEmpty == true {
                listeners.removeValue(forKey: event)
            }
        }
    }

    /// Remove all listeners for an event
    public func offAll(_ event: String) {
        eventListeners.withValue { $0.removeValue(forKey: event) }
    }

    // MARK: - Connection Event Listeners

    /// Listen for connect events
    @discardableResult
    public func onConnect(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        let wrapper = CallbackWrapper<Void> { _ in callback() }
        connectCallbacks.withValue { $0[id] = wrapper }
        return id
    }

    /// Listen for disconnect events
    @discardableResult
    public func onDisconnect(_ callback: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        let wrapper = CallbackWrapper(callback)
        disconnectCallbacks.withValue { $0[id] = wrapper }
        return id
    }

    /// Listen for error events
    @discardableResult
    public func onError(_ callback: @escaping (RealtimeErrorPayload) -> Void) -> UUID {
        let id = UUID()
        let wrapper = CallbackWrapper(callback)
        errorCallbacks.withValue { $0[id] = wrapper }
        return id
    }

    /// Listen for connection error events
    @discardableResult
    public func onConnectError(_ callback: @escaping (Error) -> Void) -> UUID {
        let id = UUID()
        let wrapper = CallbackWrapper(callback)
        connectErrorCallbacks.withValue { $0[id] = wrapper }
        return id
    }

    // MARK: - Helper Methods

    /// Get all currently subscribed channels
    public func getSubscribedChannels() -> [String] {
        Array(subscribedChannels.value)
    }

    // MARK: - Private Methods

    private func resubscribeToChannels() {
        for channel in subscribedChannels.value {
            socket?.emit("realtime:subscribe", ["channel": channel])
        }
    }

    private func handleCustomEvent(_ event: String, data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let metaDict = dict["meta"] as? [String: Any],
              let messageId = metaDict["messageId"] as? String,
              let senderType = metaDict["senderType"] as? String,
              let timestamp = metaDict["timestamp"] as? String else {
            return
        }

        let meta = SocketMessageMeta(
            channel: metaDict["channel"] as? String,
            messageId: messageId,
            senderType: senderType,
            senderId: metaDict["senderId"] as? String,
            timestamp: timestamp
        )

        // Extract payload (everything except meta)
        var payload = dict
        payload.removeValue(forKey: "meta")

        let message = SocketMessage(meta: meta, payload: payload)

        // Notify listeners
        eventListeners.withValue { listeners in
            if let callbacks = listeners[event] {
                for (_, wrapper) in callbacks {
                    wrapper.callback(message)
                }
            }
        }
    }

    private func notifyConnect() {
        connectCallbacks.withValue { callbacks in
            for (_, wrapper) in callbacks {
                wrapper.callback(())
            }
        }
    }

    private func notifyDisconnect(_ reason: String) {
        disconnectCallbacks.withValue { callbacks in
            for (_, wrapper) in callbacks {
                wrapper.callback(reason)
            }
        }
    }

    private func notifyError(_ error: RealtimeErrorPayload) {
        errorCallbacks.withValue { callbacks in
            for (_, wrapper) in callbacks {
                wrapper.callback(error)
            }
        }
    }
}

// MARK: - Legacy Models (for backwards compatibility)

/// Realtime message (matches InsForge backend schema)
public struct RealtimeMessage: Codable, Sendable {
    public let id: String?
    public let eventName: String?
    public let channelId: String?
    public let channelName: String?
    public let payload: [String: AnyCodable]?
    public let senderType: String?
    public let senderId: String?
    public let wsAudienceCount: Int?
    public let whAudienceCount: Int?
    public let whDeliveredCount: Int?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, eventName, channelId, channelName, payload, senderType, senderId
        case wsAudienceCount, whAudienceCount, whDeliveredCount, createdAt
    }
}

/// Channel model (for REST API operations, matches InsForge backend schema)
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
