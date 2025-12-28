import Foundation
import InsForgeCore
import InsForgeAuth

/// High-level Realtime channel for broadcast and postgres changes
public actor RealtimeChannel {
    private let channelName: String
    private let client: RealtimeClient
    private var isSubscribed = false
    private var broadcastContinuations: [String: [UUID: AsyncStream<BroadcastMessage>.Continuation]] = [:]
    private var postgresChangeContinuations: [String: [UUID: Any]] = [:]

    init(channelName: String, client: RealtimeClient) {
        self.channelName = channelName
        self.client = client
    }

    // MARK: - Subscription

    /// Subscribe to the channel
    /// Must be called before receiving broadcast messages or postgres changes via WebSocket
    public func subscribe() async throws {
        guard !isSubscribed else { return }

        await client.subscribe(to: channelName) { [weak self] message in
            guard let self = self else { return }
            Task {
                await self.handleMessage(message)
            }
        }

        isSubscribed = true
    }

    /// Unsubscribe from the channel
    public func unsubscribe() async {
        await client.unsubscribe(from: channelName)
        isSubscribed = false

        // Clean up all continuations
        for (_, continuations) in broadcastContinuations {
            for (_, continuation) in continuations {
                continuation.finish()
            }
        }
        broadcastContinuations.removeAll()
        postgresChangeContinuations.removeAll()
    }

    // MARK: - Broadcast

    /// Listen for broadcast messages on a specific event
    /// - Parameter event: Event name to listen for, use "*" to listen to all events
    /// - Returns: AsyncStream of broadcast messages
    public func broadcast(event: String = "*") -> AsyncStream<BroadcastMessage> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.addBroadcastContinuation(id: id, event: event, continuation: continuation)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.removeBroadcastContinuation(id: id, event: event)
                }
            }
        }
    }

    /// Send a broadcast message
    /// - Parameters:
    ///   - event: Event name
    ///   - message: Message payload (must be Encodable)
    public func broadcast<T: Encodable>(event: String, message: T) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await client.publish(to: channelName, event: event, payload: dict)
    }

    /// Send a broadcast message with dictionary payload
    /// - Parameters:
    ///   - event: Event name
    ///   - message: Message payload as dictionary
    public func broadcast(event: String, message: [String: Any]) async throws {
        try await client.publish(to: channelName, event: event, payload: message)
    }

    // MARK: - Postgres Changes

    /// Listen for postgres changes on a schema
    /// - Parameters:
    ///   - action: Type of action to listen for (AnyAction, InsertAction, UpdateAction, or DeleteAction)
    ///   - schema: Database schema name (e.g., "public")
    ///   - table: Optional table name to filter
    ///   - filter: Optional postgres filter
    /// - Returns: AsyncStream of postgres change actions
    public func postgresChange<Action: PostgresChangeAction>(
        _: Action.Type,
        schema: String,
        table: String? = nil,
        filter: String? = nil
    ) -> AsyncStream<Action> {
        AsyncStream { continuation in
            let id = UUID()
            let key = postgresChangeKey(schema: schema, table: table)

            Task {
                await self.addPostgresChangeContinuation(id: id, key: key, continuation: continuation)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.removePostgresChangeContinuation(id: id, key: key)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func addBroadcastContinuation(
        id: UUID,
        event: String,
        continuation: AsyncStream<BroadcastMessage>.Continuation
    ) {
        if broadcastContinuations[event] == nil {
            broadcastContinuations[event] = [:]
        }
        broadcastContinuations[event]?[id] = continuation
    }

    private func removeBroadcastContinuation(id: UUID, event: String) {
        broadcastContinuations[event]?.removeValue(forKey: id)
        if broadcastContinuations[event]?.isEmpty == true {
            broadcastContinuations.removeValue(forKey: event)
        }
    }

    private func addPostgresChangeContinuation<Action: PostgresChangeAction>(
        id: UUID,
        key: String,
        continuation: AsyncStream<Action>.Continuation
    ) {
        if postgresChangeContinuations[key] == nil {
            postgresChangeContinuations[key] = [:]
        }
        postgresChangeContinuations[key]?[id] = continuation
    }

    private func removePostgresChangeContinuation(id: UUID, key: String) {
        postgresChangeContinuations[key]?.removeValue(forKey: id)
        if postgresChangeContinuations[key]?.isEmpty == true {
            postgresChangeContinuations.removeValue(forKey: key)
        }
    }

    private func postgresChangeKey(schema: String, table: String?) -> String {
        if let table = table {
            return "\(schema):\(table)"
        }
        return schema
    }

    private func handleMessage(_ message: RealtimeMessage) {
        // Handle broadcast messages
        if let eventName = message.eventName {
            handleBroadcastMessage(message, event: eventName)
        }

        // Handle postgres changes
        if let payload = message.payload,
           let schema = payload["schema"]?.value as? String {
            let table = payload["table"]?.value as? String
            let key = postgresChangeKey(schema: schema, table: table)
            handlePostgresChange(message, key: key)
        }
    }

    private func handleBroadcastMessage(_ message: RealtimeMessage, event: String) {
        let broadcastMsg = BroadcastMessage(
            event: event,
            payload: message.payload ?? [:],
            senderId: message.senderId
        )

        // Send to specific event listeners
        broadcastContinuations[event]?.values.forEach { continuation in
            continuation.yield(broadcastMsg)
        }

        // Send to wildcard listeners
        broadcastContinuations["*"]?.values.forEach { continuation in
            continuation.yield(broadcastMsg)
        }
    }

    private func handlePostgresChange(_ message: RealtimeMessage, key: String) {
        guard let continuations = postgresChangeContinuations[key] else { return }

        // Try to decode and send to typed continuations
        for (_, _) in continuations {
            // TODO: Implement proper type-safe decoding and yielding
            // This requires runtime type information or a different approach
            // For now, this is a placeholder for future implementation
        }
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
