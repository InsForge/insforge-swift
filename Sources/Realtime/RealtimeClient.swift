import Foundation
import InsForgeCore
import InsForgeAuth
import SocketIO
import Logging
#if canImport(Network)
import Network
#endif

// MARK: - Connection State

/// Realtime connection state
public enum ConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
}

// MARK: - Public Options

/// Reconnect configuration for realtime socket behavior.
public struct RealtimeReconnectOptions: Sendable {
    public let initialDelay: TimeInterval
    public let multiplier: Double
    public let maxDelay: TimeInterval
    public let maxAttempts: Int
    public let jitterFactor: Double

    public init(
        initialDelay: TimeInterval = 1.0,
        multiplier: Double = 2.0,
        maxDelay: TimeInterval = 30.0,
        maxAttempts: Int = 8,
        jitterFactor: Double = 0.2
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.jitterFactor = jitterFactor
    }
}

/// Realtime client options.
public struct RealtimeOptions: Sendable {
    public let reconnect: RealtimeReconnectOptions
    public let connectionTimeout: TimeInterval

    public init(
        reconnect: RealtimeReconnectOptions = .init(),
        connectionTimeout: TimeInterval = 10
    ) {
        self.reconnect = reconnect
        self.connectionTimeout = connectionTimeout
    }
}

// MARK: - Reconnect Policy

internal struct ReconnectPolicy: Sendable {
    let initialDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval
    let maxAttempts: Int
    let jitterFactor: Double

    init(
        initialDelay: TimeInterval,
        multiplier: Double,
        maxDelay: TimeInterval,
        maxAttempts: Int,
        jitterFactor: Double
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.jitterFactor = jitterFactor
    }

    static let `default` = ReconnectPolicy(
        initialDelay: 1.0,
        multiplier: 2.0,
        maxDelay: 30.0,
        maxAttempts: 8,
        jitterFactor: 0.2
    )

    init(options: RealtimeReconnectOptions) {
        self.initialDelay = max(0, options.initialDelay)
        self.multiplier = max(1, options.multiplier)
        self.maxDelay = max(0, options.maxDelay)
        self.maxAttempts = max(0, options.maxAttempts)
        self.jitterFactor = min(max(0, options.jitterFactor), 1)
    }

    func baseDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        return min(initialDelay * pow(multiplier, Double(exponent)), maxDelay)
    }

    func applyJitter(to baseDelay: TimeInterval, randomUnit: Double) -> TimeInterval {
        let clampedRandom = min(max(randomUnit, 0), 1)
        let jitterRange = jitterFactor * 2
        let jitterMultiplier = (1 - jitterFactor) + (clampedRandom * jitterRange)
        return max(0, baseDelay * jitterMultiplier)
    }
}

internal enum ReconnectDecision: Equatable {
    case none
    case maxedOut
    case schedule(attempt: Int, baseDelay: TimeInterval)
}

internal enum NetworkAvailability: Sendable, Equatable {
    case unknown
    case available
    case unavailable
}

internal struct ReconnectRuntimeState: Sendable {
    var retryAttempt: Int = 0
    var shouldMaintainConnection: Bool = false
    var networkAvailability: NetworkAvailability = .unknown
    var isManuallyDisconnected: Bool = false

    mutating func prepareForConnectionRequest(resetRetryAttempt: Bool) {
        if resetRetryAttempt {
            retryAttempt = 0
        }
        shouldMaintainConnection = true
        isManuallyDisconnected = false
    }

    mutating func markConnectSucceeded() {
        retryAttempt = 0
        shouldMaintainConnection = true
        isManuallyDisconnected = false
    }

    mutating func markManualDisconnect() {
        retryAttempt = 0
        shouldMaintainConnection = false
        isManuallyDisconnected = true
    }

    mutating func applyNetworkAvailability(_ availability: NetworkAvailability) -> (didChange: Bool, becameAvailableFromUnavailable: Bool) {
        let previousAvailability = networkAvailability
        networkAvailability = availability

        let becameAvailableFromUnavailable = previousAvailability == .unavailable && availability == .available
        if becameAvailableFromUnavailable {
            retryAttempt = 0
        }

        return (previousAvailability != availability, becameAvailableFromUnavailable)
    }

    mutating func nextReconnectDecision(
        policy: ReconnectPolicy,
        hasPendingReconnectTask: Bool,
        hasActiveConnectTask: Bool,
        isSocketConnected: Bool
    ) -> ReconnectDecision {
        guard shouldMaintainConnection,
              !isManuallyDisconnected,
              networkAvailability != .unavailable,
              !hasPendingReconnectTask,
              !hasActiveConnectTask,
              !isSocketConnected else {
            return .none
        }

        guard retryAttempt < policy.maxAttempts else {
            shouldMaintainConnection = false
            return .maxedOut
        }

        retryAttempt += 1
        let attempt = retryAttempt
        let baseDelay = policy.baseDelay(forAttempt: attempt)
        return .schedule(attempt: attempt, baseDelay: baseDelay)
    }
}

internal struct ReconnectCoordinatorState: Sendable {
    var runtime = ReconnectRuntimeState()
    var connectTask: Task<Void, Error>?
    var connectTaskToken: UUID?
    var reconnectTask: Task<Void, Never>?
    var reconnectTaskToken: UUID?
}

private struct SocketRuntimeState {
    var manager: SocketManager?
    var socket: SocketIOClient?
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

    /// Shared decoder configured for realtime events
    /// - Uses ISO8601 date decoding strategy for date fields
    /// - Does NOT use convertFromSnakeCase because models typically define their own CodingKeys
    private static let realtimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase - let models define their own CodingKeys
        // This avoids conflicts when models already have explicit key mappings
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
        return decoder
    }()

    /// Decode payload to a specific type
    /// Uses a decoder configured for realtime events.
    ///
    /// This method provides lenient decoding for realtime events where the server
    /// may not send all fields. If decoding fails due to missing Date keys
    /// (fields containing "date", "at", or "_at"), it will automatically
    /// fill in the current date and retry decoding.
    ///
    /// This allows application models to use non-optional Date fields without
    /// implementing custom `init(from decoder:)` methods.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        var mutablePayload = payload
        var lastError: Error?

        // Try decoding up to 3 times (to handle multiple missing date fields)
        for _ in 0..<3 {
            let data = try JSONSerialization.data(withJSONObject: mutablePayload)
            do {
                return try Self.realtimeDecoder.decode(T.self, from: data)
            } catch let DecodingError.keyNotFound(key, context) {
                lastError = DecodingError.keyNotFound(key, context)

                // The key.stringValue is the CodingKey's raw value (e.g., "created_at")
                let missingKey = key.stringValue

                // Check if this looks like a date field
                // Common patterns: created_at, updated_at, due_date, reminderDate, etc.
                let isDateField = missingKey.lowercased().contains("date") ||
                                  missingKey.lowercased().contains("_at") ||
                                  missingKey.hasSuffix("At")

                if isDateField {
                    // Date field - use ISO8601 format string for current date
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    mutablePayload[missingKey] = formatter.string(from: Date())
                    continue // Retry with updated payload
                } else {
                    // For non-date fields, we can't determine the type, so rethrow
                    throw DecodingError.keyNotFound(key, context)
                }
            }
        }

        // If we exhausted retries, throw the last error
        throw lastError ?? InsForgeError.unknown("Failed to decode payload after multiple retries")
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
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    private let socketRuntimeState = LockIsolated<SocketRuntimeState>(SocketRuntimeState())
    private let subscribedChannels = LockIsolated<Set<String>>(Set())
    private let eventListeners = LockIsolated<[String: [UUID: CallbackWrapper<SocketMessage>]]>([:])
    private let reconnectCoordinator = LockIsolated<ReconnectCoordinatorState>(ReconnectCoordinatorState())
    private let reconnectPolicy: ReconnectPolicy
    private let connectionTimeout: TimeInterval
    private let reconnectErrorDomain = "InsForgeRealtimeReconnect"
    private let jitterRandomProvider: @Sendable () -> Double

#if canImport(Network)
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "com.insforge.realtime.network-monitor")
#endif

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
        options: RealtimeOptions = .init()
    ) {
        self.url = url
        self.apiKey = apiKey
        self.headersProvider = headersProvider
        self.reconnectPolicy = ReconnectPolicy(options: options.reconnect)
        self.connectionTimeout = max(0, options.connectionTimeout)
        self.jitterRandomProvider = { Double.random(in: 0...1) }
        startNetworkMonitoring()
    }

    deinit {
        cancelReconnectTask()
        cancelConnectTask()
#if canImport(Network)
        networkMonitor?.cancel()
#endif
    }

    // MARK: - Connection State

    /// Check if connected to the realtime server
    public var isConnected: Bool {
        currentSocketStatus() == .connected
    }

    /// Get the current connection state
    public var connectionState: ConnectionState {
        switch currentSocketStatus() {
        case .connected: return .connected
        case .connecting: return .connecting
        default: return .disconnected
        }
    }

    /// Get the socket ID (if connected)
    public var socketId: String? {
        currentSocket()?.sid
    }

    // MARK: - Connection

    private struct ConnectInvocation {
        let task: Task<Void, Error>
        let token: UUID
        let isOwner: Bool
    }

    /// Connect to the realtime server
    public func connect() async throws {
        try await connect(resetRetryBudget: true)
    }

    private func connect(resetRetryBudget: Bool) async throws {
        // Already connected
        if currentSocketStatus() == .connected {
            logger.debug("Already connected, skipping connect()")
            return
        }

        cancelReconnectTask()

        let invocation = reconnectCoordinator.withValue { coordinator -> ConnectInvocation in
            coordinator.runtime.prepareForConnectionRequest(resetRetryAttempt: resetRetryBudget)

            if let existingTask = coordinator.connectTask,
               let existingToken = coordinator.connectTaskToken {
                return ConnectInvocation(task: existingTask, token: existingToken, isOwner: false)
            }

            let token = UUID()
            let task = Task { [weak self] in
                guard let self = self else { return }
                try await self.performConnectAttempt()
            }

            coordinator.connectTask = task
            coordinator.connectTaskToken = token
            return ConnectInvocation(task: task, token: token, isOwner: true)
        }

        do {
            try await invocation.task.value
            if invocation.isOwner {
                clearConnectTaskIfNeeded(token: invocation.token)
            }
        } catch {
            if invocation.isOwner {
                clearConnectTaskIfNeeded(token: invocation.token)
                if !(error is CancellationError) {
                    notifyConnectError(error)
                    scheduleReconnect(reason: "connect_failed")
                }
            }
            throw error
        }
    }

    /// Disconnect from the realtime server
    public func disconnect() {
        logger.debug("Disconnecting...")

        reconnectCoordinator.withValue { coordinator in
            coordinator.runtime.markManualDisconnect()
        }

        cancelReconnectTask()
        cancelConnectTask()

        let socketToDisconnect = clearSocketRuntimeState()
        socketToDisconnect?.disconnect()
        socketToDisconnect?.removeAllHandlers()
        subscribedChannels.setValue(Set())
        logger.debug("Disconnected")
    }

    // MARK: - Event Handlers Setup

    private func setupEventHandlers(_ socket: SocketIOClient) {
        // Handle connect
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.handleSocketConnected()
        }

        // Handle disconnect
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            let reason = (data.first as? String) ?? "unknown"
            self?.handleSocketDisconnected(reason: reason)
        }

        // Handle connection errors
        socket.on(clientEvent: .error) { [weak self] data, _ in
            let error = Self.connectionError(from: data)
            self?.logError("[<<<] error: \(error.localizedDescription)")
        }

        // Handle reconnect attempts
        socket.on(clientEvent: .reconnect) { [weak self] data, _ in
            self?.logDebug("[<<<] reconnect: \(data)")
        }

        socket.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            self?.logDebug("[<<<] reconnectAttempt: \(data)")
        }

        // Handle status changes
        socket.on(clientEvent: .statusChange) { [weak self] data, _ in
            self?.logDebug("[<<<] statusChange: \(data)")
        }

        // Handle realtime errors
        socket.on("realtime:error") { [weak self] data, _ in
            self?.logDebug("[<<<] realtime:error: \(data)")

            guard let dict = data.first as? [String: Any],
                  let code = dict["code"] as? String,
                  let message = dict["message"] as? String else {
                return
            }

            let error = RealtimeErrorPayload(
                channel: dict["channel"] as? String,
                code: code,
                message: message
            )
            self?.notifyError(error)
        }

        // Handle all other events (custom events from server)
        socket.onAny { [weak self] event in
            // Log ALL incoming events
            self?.logTrace("[<<<] \(event.event): \(event.items ?? [])")

            // Skip system events for custom handler
            guard !event.event.starts(with: "realtime:"),
                  event.event != "connect",
                  event.event != "disconnect",
                  event.event != "error",
                  event.event != "reconnect",
                  event.event != "reconnectAttempt",
                  event.event != "statusChange" else {
                return
            }

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
            logger.debug("Already subscribed to '\(channel)'")
            return .success(channel: channel)
        }

        // Auto-connect if not connected
        if currentSocketStatus() != .connected {
            do {
                try await connect()
            } catch {
                logger.error("Auto-connect failed: \(error.localizedDescription)")
                return .failure(channel: channel, code: "CONNECTION_FAILED", message: error.localizedDescription)
            }
        }

        guard let socket = currentSocket() else {
            return .failure(channel: channel, code: "NO_SOCKET", message: "Socket not initialized")
        }

        let subscribePayload = ["channel": channel]
        logger.debug("[>>>] realtime:subscribe: \(subscribePayload)")

        // Emit subscribe event and wait for acknowledgment
        return await withCheckedContinuation { [weak self] continuation in
            socket.emitWithAck("realtime:subscribe", subscribePayload).timingOut(after: 10) { [weak self] data in
                self?.logDebug("[<<<] realtime:subscribe ACK: \(data)")

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
                    _ = self?.subscribedChannels.withValue { $0.insert(channel) }
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
        _ = subscribedChannels.withValue { $0.remove(channel) }

        if let socket = connectedSocketForIO() {
            let unsubscribePayload = ["channel": channel]
            logger.debug("[>>>] realtime:unsubscribe: \(unsubscribePayload)")
            socket.emit("realtime:unsubscribe", unsubscribePayload)
        }
    }

    // MARK: - Publish

    /// Publish a message to a channel
    /// - Parameters:
    ///   - channel: Channel name
    ///   - event: Event name
    ///   - payload: Message payload
    public func publish(to channel: String, event: String, payload: [String: Any]) throws {
        guard let socket = connectedSocketForIO() else {
            throw InsForgeError.unknown("Not connected to realtime server. Call connect() first.")
        }

        let publishPayload: [String: Any] = [
            "channel": channel,
            "event": event,
            "payload": payload
        ]

        logger.debug("[>>>] realtime:publish: \(publishPayload)")
        socket.emit("realtime:publish", publishPayload)
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
        _ = eventListeners.withValue { $0.removeValue(forKey: event) }
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

    private func currentSocket() -> SocketIOClient? {
        socketRuntimeState.value.socket
    }

    private func currentSocketStatus() -> SocketIOStatus {
        socketRuntimeState.value.socket?.status ?? .disconnected
    }

    private func connectedSocketForIO() -> SocketIOClient? {
        socketRuntimeState.withValue { state in
            guard state.socket?.status == .connected else {
                return nil
            }
            return state.socket
        }
    }

    private func clearSocketRuntimeState() -> SocketIOClient? {
        socketRuntimeState.withValue { state in
            let activeSocket = state.socket
            state.socket = nil
            state.manager = nil
            return activeSocket
        }
    }

    private func initializeSocketRuntimeIfNeeded(manager: SocketManager, socket: SocketIOClient) -> SocketIOClient {
        socketRuntimeState.withValue { state in
            if let existingSocket = state.socket {
                return existingSocket
            }

            state.manager = manager
            state.socket = socket
            return socket
        }
    }

    private func currentAuthToken() -> String {
        let headers = headersProvider.value
        return headers["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? apiKey
    }

    private func performConnectAttempt() async throws {
        let runtimeState = reconnectCoordinator.value.runtime
        guard runtimeState.networkAvailability != .unavailable else {
            throw NSError(
                domain: reconnectErrorDomain,
                code: -1009,
                userInfo: [NSLocalizedDescriptionKey: "Network is unavailable. Waiting for connectivity to resume."]
            )
        }

        let socket = try ensureSocketInitialized()
        let authToken = currentAuthToken()
        let authPayload = ["token": authToken]

        logDebug("Connecting to: \(url.absoluteString)")
        logTrace("Auth token: \(String(authToken.prefix(20)))...")

        let cancellationHook = LockIsolated<(() -> Void)?>(nil)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
                guard let self = self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                struct ConnectAttemptCompletionState {
                    var completed = false
                    var connectHandlerId: UUID?
                    var errorHandlerId: UUID?
                }
                let completionState = LockIsolated(ConnectAttemptCompletionState())

                func complete(with result: Result<Void, Error>) {
                    let handlerIds = completionState.withValue { state -> (UUID?, UUID?)? in
                        guard !state.completed else { return nil }
                        state.completed = true
                        return (state.connectHandlerId, state.errorHandlerId)
                    }

                    guard let handlerIds else { return }
                    cancellationHook.setValue(nil)

                    if let connectHandlerId = handlerIds.0 {
                        socket.off(id: connectHandlerId)
                    }

                    if let errorHandlerId = handlerIds.1 {
                        socket.off(id: errorHandlerId)
                    }

                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                let connectHandlerId = socket.on(clientEvent: .connect) { _, _ in
                    complete(with: .success(()))
                }
                completionState.withValue { $0.connectHandlerId = connectHandlerId }

                let errorHandlerId = socket.on(clientEvent: .error) { data, _ in
                    complete(with: .failure(Self.connectionError(from: data)))
                }
                completionState.withValue { $0.errorHandlerId = errorHandlerId }

                cancellationHook.setValue {
                    complete(with: .failure(CancellationError()))
                }

                if Task.isCancelled {
                    complete(with: .failure(CancellationError()))
                    return
                }

                socket.connect(withPayload: authPayload, timeoutAfter: self.connectionTimeout) {
                    complete(with: .failure(
                        NSError(
                            domain: self.reconnectErrorDomain,
                            code: -1001,
                            userInfo: [NSLocalizedDescriptionKey: "Connection timed out after \(Int(self.connectionTimeout)) seconds."]
                        )
                    ))
                }
            }
        }, onCancel: {
            let hook = cancellationHook.withValue { hook -> (() -> Void)? in
                let activeHook = hook
                hook = nil
                return activeHook
            }
            hook?()
        })
    }

    private func ensureSocketInitialized() throws -> SocketIOClient {
        if let socket = currentSocket() {
            return socket
        }

        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(false)
        ]

        let manager = SocketManager(socketURL: url, config: config)
        let newSocket = manager.defaultSocket

        setupEventHandlers(newSocket)
        let activeSocket = initializeSocketRuntimeIfNeeded(manager: manager, socket: newSocket)
        if activeSocket !== newSocket {
            newSocket.removeAllHandlers()
            newSocket.disconnect()
        }
        return activeSocket
    }

    private func clearConnectTaskIfNeeded(token: UUID) {
        reconnectCoordinator.withValue { coordinator in
            guard coordinator.connectTaskToken == token else { return }
            coordinator.connectTask = nil
            coordinator.connectTaskToken = nil
        }
    }

    private func clearReconnectTaskIfNeeded(token: UUID) {
        reconnectCoordinator.withValue { coordinator in
            guard coordinator.reconnectTaskToken == token else { return }
            coordinator.reconnectTask = nil
            coordinator.reconnectTaskToken = nil
        }
    }

    private func cancelConnectTask() {
        let task = reconnectCoordinator.withValue { coordinator -> Task<Void, Error>? in
            let activeTask = coordinator.connectTask
            coordinator.connectTask = nil
            coordinator.connectTaskToken = nil
            return activeTask
        }

        task?.cancel()
    }

    private func cancelReconnectTask() {
        let task = reconnectCoordinator.withValue { coordinator -> Task<Void, Never>? in
            let activeTask = coordinator.reconnectTask
            coordinator.reconnectTask = nil
            coordinator.reconnectTaskToken = nil
            return activeTask
        }

        task?.cancel()
    }

    private func scheduleReconnect(reason: String) {
        struct ReconnectScheduleReservation {
            let token: UUID
            let attempt: Int
            let delay: TimeInterval
        }

        var scheduledAttempt: Int?
        var scheduledDelay: TimeInterval?
        var shouldEmitMaxRetryError = false
        var reservation: ReconnectScheduleReservation?
        let isSocketConnected = currentSocketStatus() == .connected

        reconnectCoordinator.withValue { coordinator in
            let decision = coordinator.runtime.nextReconnectDecision(
                policy: reconnectPolicy,
                hasPendingReconnectTask: coordinator.reconnectTask != nil || coordinator.reconnectTaskToken != nil,
                hasActiveConnectTask: coordinator.connectTask != nil,
                isSocketConnected: isSocketConnected
            )

            switch decision {
            case .none:
                return
            case .maxedOut:
                shouldEmitMaxRetryError = true
            case .schedule(let attempt, let baseDelay):
                let delay = computeReconnectDelay(baseDelay: baseDelay)
                let token = UUID()

                coordinator.reconnectTaskToken = token
                coordinator.reconnectTask = nil
                reservation = ReconnectScheduleReservation(token: token, attempt: attempt, delay: delay)
                scheduledAttempt = attempt
                scheduledDelay = delay
            }
        }

        if let reservation {
            let reconnectTask = Task { [weak self] in
                guard let self = self else { return }

                do {
                    try await Task.sleep(nanoseconds: UInt64(reservation.delay * 1_000_000_000))
                } catch {
                    return
                }

                self.clearReconnectTaskIfNeeded(token: reservation.token)

                do {
                    try await self.connect(resetRetryBudget: false)
                } catch {
                    guard !(error is CancellationError) else { return }
                    self.logError("Reconnect attempt \(reservation.attempt) failed: \(error.localizedDescription)")
                    self.scheduleReconnect(reason: "reconnect_attempt_\(reservation.attempt)_failed")
                }
            }

            let didAttach = reconnectCoordinator.withValue { coordinator -> Bool in
                guard coordinator.reconnectTaskToken == reservation.token,
                      coordinator.reconnectTask == nil else {
                    return false
                }

                coordinator.reconnectTask = reconnectTask
                return true
            }

            if !didAttach {
                reconnectTask.cancel()
            }
        }

        if let scheduledAttempt, let scheduledDelay {
            logDebug(
                "Scheduling reconnect attempt \(scheduledAttempt)/\(reconnectPolicy.maxAttempts) " +
                "in \(String(format: "%.2f", scheduledDelay))s (reason: \(reason))"
            )
        }

        if shouldEmitMaxRetryError {
            emitMaxReconnectAttemptsError()
        }
    }

    private func computeReconnectDelay(baseDelay: TimeInterval) -> TimeInterval {
        reconnectPolicy.applyJitter(to: baseDelay, randomUnit: jitterRandomProvider())
    }

    private func handleSocketConnected() {
        let reconnectTaskToCancel = reconnectCoordinator.withValue { coordinator -> Task<Void, Never>? in
            coordinator.runtime.markConnectSucceeded()
            let activeReconnectTask = coordinator.reconnectTask
            coordinator.reconnectTask = nil
            coordinator.reconnectTaskToken = nil
            return activeReconnectTask
        }

        reconnectTaskToCancel?.cancel()
        logDebug("Connected successfully, Socket ID: \(currentSocket()?.sid ?? "unknown")")
        resubscribeToChannels()
        notifyConnect()
    }

    private func handleSocketDisconnected(reason: String) {
        logDebug("[<<<] disconnect: \(reason)")
        notifyDisconnect(reason)

        let shouldReconnect = reconnectCoordinator.withValue { coordinator in
            coordinator.runtime.shouldMaintainConnection &&
            !coordinator.runtime.isManuallyDisconnected
        }

        guard shouldReconnect else {
            return
        }

        scheduleReconnect(reason: "disconnect_\(reason)")
    }

    private func emitMaxReconnectAttemptsError() {
        let payload = RealtimeErrorPayload(
            channel: nil,
            code: "MAX_RECONNECT_ATTEMPTS",
            message: "Reconnect exhausted after \(reconnectPolicy.maxAttempts) attempts."
        )
        logError(payload.message)
        notifyError(payload)
    }

    private func handleNetworkAvailabilityChange(_ availability: NetworkAvailability) {
        let transition = reconnectCoordinator.withValue { coordinator in
            coordinator.runtime.applyNetworkAvailability(availability)
        }

        guard transition.didChange else { return }

        switch availability {
        case .available:
            if transition.becameAvailableFromUnavailable {
                logDebug("Network restored. Reconnect retry counter reset.")
            }
            logDebug("Network is reachable. Evaluating pending reconnect flow.")
            scheduleReconnect(reason: "network_available")
        case .unavailable:
            logDebug("Network is unavailable. Pausing reconnect attempts.")
            cancelReconnectTask()
        case .unknown:
            break
        }
    }

    private func startNetworkMonitoring() {
#if canImport(Network)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let availability: NetworkAvailability = path.status == .satisfied ? .available : .unavailable
            self?.handleNetworkAvailabilityChange(availability)
        }
        monitor.start(queue: networkMonitorQueue)
        networkMonitor = monitor
#endif
    }

    private static func connectionError(from data: [Any]) -> Error {
        if let error = data.first as? Error {
            return error
        }

        if let message = data.first as? String {
            return NSError(
                domain: "RealtimeClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return NSError(
            domain: "RealtimeClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown connection error."]
        )
    }

    private func resubscribeToChannels() {
        guard let socket = connectedSocketForIO() else { return }
        let channels = subscribedChannels.value
        for channel in channels {
            let payload = ["channel": channel]
            logger.debug("[>>>] realtime:subscribe (re-subscribe): \(payload)")
            socket.emit("realtime:subscribe", payload)
        }
    }

    // MARK: - Logging Helpers (for use in closures)

    private func logDebug(_ message: String) {
        logger.debug("\(message)")
    }

    private func logTrace(_ message: String) {
        logger.trace("\(message)")
    }

    private func logError(_ message: String) {
        logger.error("\(message)")
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

    private func notifyConnectError(_ error: Error) {
        connectErrorCallbacks.withValue { callbacks in
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
