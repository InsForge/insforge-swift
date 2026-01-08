import Foundation
import InsForgeCore
import InsForgeAuth

/// High-level Realtime channel for subscribing and broadcasting messages
///
/// Example usage:
/// ```swift
/// let channel = realtime.channel("orders:123")
///
/// // Subscribe to the channel
/// let response = await channel.subscribe()
/// if response.ok {
///     print("Subscribed to channel")
/// }
///
/// // Listen for specific events
/// channel.on("order_updated") { message in
///     print("Order updated:", message.payload)
/// }
///
/// // Send a broadcast message
/// try channel.broadcast(event: "status_changed", message: ["status": "shipped"])
///
/// // Unsubscribe when done
/// channel.unsubscribe()
/// ```
public final class RealtimeChannelWrapper: @unchecked Sendable {
    private let channelName: String
    private let client: RealtimeClient
    private var isSubscribed = false
    private var listenerIds = LockIsolated<[UUID]>([])

    init(channelName: String, client: RealtimeClient) {
        self.channelName = channelName
        self.client = client
    }

    /// The name of this channel
    public var name: String {
        channelName
    }

    // MARK: - Subscription

    /// Subscribe to the channel
    /// - Returns: Subscribe response indicating success or failure
    public func subscribe() async -> SubscribeResponse {
        guard !isSubscribed else {
            return .success(channel: channelName)
        }

        let response = await client.subscribe(channelName)
        if response.ok {
            isSubscribed = true
        }
        return response
    }

    /// Unsubscribe from the channel
    public func unsubscribe() {
        client.unsubscribe(from: channelName)
        isSubscribed = false

        // Remove all event listeners for this channel
        listenerIds.withValue { ids in
            ids.removeAll()
        }
    }

    /// Check if currently subscribed
    public var subscribed: Bool {
        isSubscribed
    }

    // MARK: - Event Listening

    /// Listen for events on this channel
    /// - Parameters:
    ///   - event: Event name to listen for
    ///   - callback: Callback when event is received
    /// - Returns: Listener ID for removal
    @discardableResult
    public func on(_ event: String, callback: @escaping (SocketMessage) -> Void) -> UUID {
        let id = client.on(event) { [weak self] message in
            guard let self = self else { return }
            // Only forward messages for this channel
            // Server may send channel as "realtime:{channelName}" or just "{channelName}"
            let messageChannel = message.meta.channel ?? ""
            let matches = messageChannel == self.channelName ||
                          messageChannel == "realtime:\(self.channelName)"
            if matches {
                callback(message)
            }
        }
        listenerIds.withValue { $0.append(id) }
        return id
    }

    /// Remove a listener
    public func off(_ event: String, id: UUID) {
        client.off(event, id: id)
        listenerIds.withValue { $0.removeAll { $0 == id } }
    }

    // MARK: - Broadcasting

    /// Send a broadcast message with dictionary payload
    /// - Parameters:
    ///   - event: Event name
    ///   - message: Message payload as dictionary
    public func broadcast(event: String, message: [String: Any]) throws {
        try client.publish(to: channelName, event: event, payload: message)
    }

    /// Send a broadcast message with Encodable payload
    /// - Parameters:
    ///   - event: Event name
    ///   - message: Message payload (must be Encodable)
    public func broadcast<T: Encodable>(event: String, message: T) throws {
        try client.publish(to: channelName, event: event, payload: message)
    }
}

// MARK: - Broadcast Message

/// Broadcast message received from the channel
public struct BroadcastMessage: Sendable {
    public let event: String
    public let payload: [String: AnyCodable]
    public let senderId: String?

    /// Decode the payload to a specific type
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload.mapValues { $0.value })
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - RealtimeClient Extension for Channel API

extension RealtimeClient {
    /// Get or create a channel wrapper for high-level operations
    /// - Parameter channelName: Name of the channel
    /// - Returns: RealtimeChannelWrapper instance
    public func channel(_ channelName: String) -> RealtimeChannelWrapper {
        RealtimeChannelWrapper(channelName: channelName, client: self)
    }
}
