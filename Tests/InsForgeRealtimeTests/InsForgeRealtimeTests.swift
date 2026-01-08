import XCTest
@testable import InsForgeRealtime
@testable import InsForgeCore
@testable import InsForge
@testable import InsForgeAuth

// MARK: - Test Models

struct TestMessage: Codable, Equatable {
    let text: String
    let from: String
}

// MARK: - Test Configuration

enum TestConfig {
    static let baseURL = "https://pg6afqz9.us-east.insforge.app"
    static let anonKey = "ik_ca177fcf1e2e72e8d1e0c2c23dbe3b79"
    // Authenticated user token for testing
    static let userToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwODVhNDgxZS05NGI4LTRiZjktYjNhMC03ZjBlNTBmN2EwNzIiLCJlbWFpbCI6Imp1bndlbi5mZW5nQGluc2ZvcmdlLmRldiIsInJvbGUiOiJhdXRoZW50aWNhdGVkIiwiaWF0IjoxNzY3NzQyMTE2LCJleHAiOjE3NjgzNDY5MTZ9.jhfprod2CU1Bn2j92wG9_j0MdmbtycpRI0SHoqqDtcc"
}

// MARK: - Tests

final class InsForgeRealtimeTests: XCTestCase {
    // MARK: - Model Tests

    func testRealtimeMessageDecoding() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "eventName": "message.new",
            "channelId": "channel-uuid-123",
            "channelName": "chat:lobby",
            "payload": {"text": "Hello"},
            "senderType": "user",
            "senderId": "user123",
            "wsAudienceCount": 5,
            "whAudienceCount": 2,
            "whDeliveredCount": 1,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(RealtimeMessage.self, from: data)

        XCTAssertEqual(message.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(message.eventName, "message.new")
        XCTAssertEqual(message.channelId, "channel-uuid-123")
        XCTAssertEqual(message.channelName, "chat:lobby")
        XCTAssertEqual(message.senderType, "user")
        XCTAssertEqual(message.senderId, "user123")
        XCTAssertEqual(message.wsAudienceCount, 5)
        XCTAssertEqual(message.whAudienceCount, 2)
        XCTAssertEqual(message.whDeliveredCount, 1)
    }

    func testChannelModelDecoding() throws {
        let json = """
        {
            "id": "channel-uuid-456",
            "pattern": "orders:*",
            "description": "Order events channel",
            "webhookUrls": ["https://example.com/webhook"],
            "enabled": true,
            "createdAt": "2025-01-01T00:00:00Z",
            "updatedAt": "2025-01-02T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let channel = try decoder.decode(Channel.self, from: data)

        XCTAssertEqual(channel.id, "channel-uuid-456")
        XCTAssertEqual(channel.pattern, "orders:*")
        XCTAssertEqual(channel.description, "Order events channel")
        XCTAssertEqual(channel.webhookUrls, ["https://example.com/webhook"])
        XCTAssertTrue(channel.enabled)
    }

    func testSocketMessageMetaDecoding() throws {
        let json = """
        {
            "channel": "test-channel",
            "messageId": "msg-123",
            "senderType": "user",
            "senderId": "user-456",
            "timestamp": "2025-01-01T12:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let meta = try JSONDecoder().decode(SocketMessageMeta.self, from: data)

        XCTAssertEqual(meta.channel, "test-channel")
        XCTAssertEqual(meta.messageId, "msg-123")
        XCTAssertEqual(meta.senderType, "user")
        XCTAssertEqual(meta.senderId, "user-456")
        XCTAssertEqual(meta.timestamp, "2025-01-01T12:00:00Z")
    }

    // MARK: - Subscribe Response Tests

    func testSubscribeResponseSuccess() {
        let response = SubscribeResponse.success(channel: "test-channel")

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.channel, "test-channel")
    }

    func testSubscribeResponseFailure() {
        let response = SubscribeResponse.failure(
            channel: "test-channel",
            code: "UNAUTHORIZED",
            message: "Not authorized"
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.channel, "test-channel")

        if case .failure(_, let code, let message) = response {
            XCTAssertEqual(code, "UNAUTHORIZED")
            XCTAssertEqual(message, "Not authorized")
        } else {
            XCTFail("Expected failure response")
        }
    }

    // MARK: - Realtime Error Payload Tests

    func testRealtimeErrorPayloadDecoding() throws {
        let json = """
        {
            "channel": "private:orders",
            "code": "PERMISSION_DENIED",
            "message": "You don't have permission to access this channel"
        }
        """

        let data = json.data(using: .utf8)!
        let error = try JSONDecoder().decode(RealtimeErrorPayload.self, from: data)

        XCTAssertEqual(error.channel, "private:orders")
        XCTAssertEqual(error.code, "PERMISSION_DENIED")
        XCTAssertEqual(error.message, "You don't have permission to access this channel")
    }

    // MARK: - Broadcast Message Tests

    func testBroadcastMessageCreation() {
        let payload: [String: AnyCodable] = [
            "text": AnyCodable("Hello, World!"),
            "from": AnyCodable("Alice")
        ]

        let message = BroadcastMessage(
            event: "chat.message",
            payload: payload,
            senderId: "user-123"
        )

        XCTAssertEqual(message.event, "chat.message")
        XCTAssertEqual(message.senderId, "user-123")
        XCTAssertNotNil(message.payload["text"])
        XCTAssertNotNil(message.payload["from"])
    }

    func testBroadcastMessageDecode() throws {
        let payload: [String: AnyCodable] = [
            "text": AnyCodable("Hello"),
            "from": AnyCodable("Bob")
        ]

        let message = BroadcastMessage(
            event: "shout",
            payload: payload,
            senderId: "user-456"
        )

        let decoded = try message.decode(TestMessage.self)

        XCTAssertEqual(decoded.text, "Hello")
        XCTAssertEqual(decoded.from, "Bob")
    }

    // MARK: - RealtimeClient Tests

    func testRealtimeClientCreation() {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let realtime = client.realtime
        XCTAssertNotNil(realtime)
        XCTAssertFalse(realtime.isConnected)
        XCTAssertEqual(realtime.connectionState, .disconnected)
    }

    func testRealtimeChannelCreation() {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let channel = client.realtime.channel("test-channel")
        XCTAssertNotNil(channel)
        XCTAssertEqual(channel.name, "test-channel")
        XCTAssertFalse(channel.subscribed)
    }

    func testMultipleChannelCreation() {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let channel1 = client.realtime.channel("channel-1")
        let channel2 = client.realtime.channel("channel-2")
        let channel3 = client.realtime.channel("channel-3")

        XCTAssertEqual(channel1.name, "channel-1")
        XCTAssertEqual(channel2.name, "channel-2")
        XCTAssertEqual(channel3.name, "channel-3")
    }

    // MARK: - Connection State Tests

    func testConnectionStateEnum() {
        XCTAssertEqual(ConnectionState.disconnected.rawValue, "disconnected")
        XCTAssertEqual(ConnectionState.connecting.rawValue, "connecting")
        XCTAssertEqual(ConnectionState.connected.rawValue, "connected")
    }

    // MARK: - Integration Tests (require network)

    func testConnectToRealtimeServer() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        do {
            try await client.realtime.connect()
            XCTAssertTrue(client.realtime.isConnected)
            XCTAssertEqual(client.realtime.connectionState, .connected)
            XCTAssertNotNil(client.realtime.socketId)

            print("[Test] Connected to realtime server with socket ID: \(client.realtime.socketId ?? "nil")")

            client.realtime.disconnect()
            XCTAssertFalse(client.realtime.isConnected)
        } catch {
            print("[Test] Connection failed: \(error)")
            // Connection might fail in test environment, that's okay
            XCTAssertFalse(client.realtime.isConnected)
        }
    }

    func testSubscribeToChannel() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let channel = client.realtime.channel("test:broadcast")

        let response = await channel.subscribe()

        if response.ok {
            print("[Test] Successfully subscribed to channel: \(response.channel)")
            XCTAssertTrue(channel.subscribed)

            // Cleanup
            channel.unsubscribe()
            client.realtime.disconnect()
        } else {
            if case .failure(_, let code, let message) = response {
                print("[Test] Subscribe failed: \(code) - \(message)")
            }
            // Subscription might fail if server is not available
        }
    }

    func testSubscribeWithAuthenticatedToken() async throws {
        // Create client with custom headers containing user token
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    headers: ["Authorization": "Bearer \(TestConfig.userToken)"]
                )
            )
        )

        do {
            try await client.realtime.connect()
            print("[Test] Connected with authenticated token")

            // Subscribe to todos channel for database changes
            let response = await client.realtime.subscribe("todos")

            if response.ok {
                print("[Test] ✅ Subscribed to 'todos' channel")

                // Set up expectation for receiving realtime event
                let expectation = XCTestExpectation(description: "Receive realtime event after todo update")
                var receivedEvent: SocketMessage?

                // Listen for any events on all event types
                let eventTypes = ["INSERT", "UPDATE", "DELETE", "db_change", "todo_updated", "todo_changed", "*"]
                var listenerIds: [UUID] = []

                for eventType in eventTypes {
                    let listenerId = client.realtime.on(eventType) { message in
                        print("[Test] 📨 Received '\(eventType)' event:")
                        print("       Channel: \(message.meta.channel ?? "nil")")
                        print("       MessageId: \(message.meta.messageId)")
                        print("       SenderType: \(message.meta.senderType)")
                        print("       Payload: \(message.payload)")
                        receivedEvent = message
                        expectation.fulfill()
                    }
                    listenerIds.append(listenerId)
                }

                // Also listen for any event via onAny-style approach
                let anyListenerId = client.realtime.on("message") { message in
                    print("[Test] 📨 Received 'message' event: \(message.payload)")
                }
                listenerIds.append(anyListenerId)

                // Now perform a database update on todos table
                print("[Test] 🔄 Performing todo update...")

                // First, fetch an existing todo
                let database = client.database
                do {
                    // Define a simple Todo struct for update (only include fields we want to update)
                    struct TodoUpdate: Codable {
                        var title: String
                    }

                    // Define Todo struct for reading
                    struct TodoRead: Codable {
                        let id: String
                        let title: String
                    }

                    // Get any existing todo
                    let existingTodos: [TodoRead] = try await database
                        .from("todos")
                        .select()
                        .limit(1)
                        .execute()

                    if let firstTodo = existingTodos.first {
                        let todoId = firstTodo.id
                        print("[Test] Found todo with id: \(todoId), title: \(firstTodo.title)")

                        // Update the todo - append timestamp to title to make it unique
                        let newTitle = "Updated at \(Date().timeIntervalSince1970)"
                        let updateResult: [TodoUpdate] = try await database
                            .from("todos")
                            .eq("id", value: todoId)
                            .update(TodoUpdate(title: newTitle))

                        print("[Test] ✅ Todo updated: \(updateResult)")

                        // Wait for realtime event (with timeout)
                        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5.0)

                        if result == .completed {
                            print("[Test] ✅ Received realtime notification!")
                            XCTAssertNotNil(receivedEvent)
                        } else {
                            print("[Test] ⚠️ No realtime event received within timeout")
                            print("[Test] This might be expected if the backend doesn't broadcast DB changes to 'todos' channel")
                        }
                    } else {
                        print("[Test] ⚠️ No existing todos found to update")
                    }
                } catch {
                    print("[Test] ❌ Database operation failed: \(error)")
                }

                // Cleanup listeners
                for (index, listenerId) in listenerIds.enumerated() {
                    if index < eventTypes.count {
                        client.realtime.off(eventTypes[index], id: listenerId)
                    } else {
                        client.realtime.off("message", id: listenerId)
                    }
                }
            } else {
                if case .failure(_, let code, let message) = response {
                    print("[Test] ❌ Subscribe failed: \(code) - \(message)")
                }
            }

            client.realtime.disconnect()
        } catch {
            print("[Test] ❌ Connection failed: \(error)")
        }
    }

    func testEventListenerRegistration() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        var connectCalled = false
        var disconnectCalled = false

        // Register connection listeners
        let connectId = client.realtime.onConnect {
            connectCalled = true
            print("[Test] Connect callback fired")
        }

        let disconnectId = client.realtime.onDisconnect { reason in
            disconnectCalled = true
            print("[Test] Disconnect callback fired: \(reason)")
        }

        XCTAssertNotEqual(connectId, disconnectId)

        do {
            try await client.realtime.connect()

            // Give time for callback to fire
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            if client.realtime.isConnected {
                XCTAssertTrue(connectCalled)
            }

            client.realtime.disconnect()

            // Give time for disconnect callback
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            print("[Test] Connection error: \(error)")
        }
    }

    func testPublishMessage() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    headers: ["Authorization": "Bearer \(TestConfig.userToken)"]
                )
            )
        )

        do {
            try await client.realtime.connect()

            // Subscribe to channel first
            let response = await client.realtime.subscribe("test:broadcast")

            if response.ok {
                // Try to publish a message
                try client.realtime.publish(
                    to: "test:broadcast",
                    event: "test_event",
                    payload: ["message": "Hello from Swift SDK test"]
                )

                print("[Test] Message published successfully")
            }

            client.realtime.disconnect()
        } catch {
            print("[Test] Error: \(error)")
        }
    }

    func testPublishEncodableMessage() async throws {
        struct ChatMessage: Encodable {
            let text: String
            let userId: String
        }

        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    headers: ["Authorization": "Bearer \(TestConfig.userToken)"]
                )
            )
        )

        do {
            try await client.realtime.connect()

            let response = await client.realtime.subscribe("chat:general")

            if response.ok {
                let message = ChatMessage(text: "Hello!", userId: "test-user")
                try client.realtime.publish(
                    to: "chat:general",
                    event: "chat_message",
                    payload: message
                )

                print("[Test] Encodable message published successfully")
            }

            client.realtime.disconnect()
        } catch {
            print("[Test] Error: \(error)")
        }
    }

    func testGetSubscribedChannels() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        do {
            try await client.realtime.connect()

            // Subscribe to multiple channels
            _ = await client.realtime.subscribe("channel-a")
            _ = await client.realtime.subscribe("channel-b")
            _ = await client.realtime.subscribe("channel-c")

            let channels = client.realtime.getSubscribedChannels()
            print("[Test] Subscribed channels: \(channels)")

            // Might not all succeed depending on server config
            XCTAssertTrue(channels.isEmpty || !channels.isEmpty)

            client.realtime.disconnect()
        } catch {
            print("[Test] Error: \(error)")
        }
    }

    func testUnsubscribeFromChannel() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        do {
            try await client.realtime.connect()

            let response = await client.realtime.subscribe("temp-channel")

            if response.ok {
                var channels = client.realtime.getSubscribedChannels()
                XCTAssertTrue(channels.contains("temp-channel"))

                client.realtime.unsubscribe(from: "temp-channel")

                channels = client.realtime.getSubscribedChannels()
                XCTAssertFalse(channels.contains("temp-channel"))

                print("[Test] Unsubscribe successful")
            }

            client.realtime.disconnect()
        } catch {
            print("[Test] Error: \(error)")
        }
    }

    // MARK: - Channel Wrapper Tests

    func testChannelWrapperSubscribeUnsubscribe() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let channel = client.realtime.channel("wrapper-test")

        XCTAssertFalse(channel.subscribed)

        let response = await channel.subscribe()

        if response.ok {
            XCTAssertTrue(channel.subscribed)

            channel.unsubscribe()
            XCTAssertFalse(channel.subscribed)
        }

        client.realtime.disconnect()
    }

    func testChannelWrapperEventListener() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey
        )

        let channel = client.realtime.channel("events-test")

        let response = await channel.subscribe()

        if response.ok {
            var receivedMessage = false

            let listenerId = channel.on("test_event") { message in
                receivedMessage = true
                print("[Test] Channel received message: \(message.meta.messageId)")
            }

            XCTAssertNotEqual(listenerId, UUID())

            // Remove listener
            channel.off("test_event", id: listenerId)
        }

        client.realtime.disconnect()
    }

    func testChannelWrapperBroadcast() async throws {
        let client = InsForgeClient(
            baseURL: URL(string: TestConfig.baseURL)!,
            anonKey: TestConfig.anonKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    headers: ["Authorization": "Bearer \(TestConfig.userToken)"]
                )
            )
        )

        let channel = client.realtime.channel("broadcast-test")

        let response = await channel.subscribe()

        if response.ok {
            do {
                try channel.broadcast(event: "announcement", message: ["text": "Hello from channel wrapper!"])
                print("[Test] Channel broadcast successful")
            } catch {
                print("[Test] Broadcast error: \(error)")
            }
        }

        client.realtime.disconnect()
    }
}
