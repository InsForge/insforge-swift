import XCTest
@testable import InsForgeRealtime
@testable import InsForgeCore
@testable import InsForge
@testable import InsForgeAuth

// MARK: - Test Models

struct TestTodo: Codable, Equatable {
    let id: String
    var title: String
    var isCompleted: Bool
    var userId: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted = "is_completed"
        case userId = "user_id"
    }
}

struct TestMessage: Codable, Equatable {
    let text: String
    let from: String
}

// MARK: - Tests

final class InsForgeRealtimeTests: XCTestCase {

    // MARK: - Basic Message Tests

    func testRealtimeMessageDecoding() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "eventName": "message.new",
            "channelName": "chat:lobby",
            "payload": {"text": "Hello"},
            "senderType": "user",
            "senderId": "user123",
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(RealtimeMessage.self, from: data)

        XCTAssertEqual(message.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(message.eventName, "message.new")
        XCTAssertEqual(message.channelName, "chat:lobby")
        XCTAssertEqual(message.senderType, "user")
    }

    // MARK: - Postgres Change Action Tests

    func testInsertActionDecoding() throws {
        let json = """
        {
            "type": "INSERT",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "Test Todo",
                "is_completed": false,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T10:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(InsertAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.type, "INSERT")
        XCTAssertEqual(action.schema, "public")
        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.record.id, "todo-123")
        XCTAssertEqual(action.record.title, "Test Todo")
        XCTAssertFalse(action.record.isCompleted)
        XCTAssertNotNil(action.commitTimestamp)
    }

    func testUpdateActionDecoding() throws {
        let json = """
        {
            "type": "UPDATE",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "Updated Todo",
                "is_completed": true,
                "user_id": "user-456"
            },
            "old_record": {
                "id": "todo-123",
                "title": "Test Todo",
                "is_completed": false,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T11:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(UpdateAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.type, "UPDATE")
        XCTAssertEqual(action.schema, "public")
        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.record.title, "Updated Todo")
        XCTAssertTrue(action.record.isCompleted)
        XCTAssertEqual(action.oldRecord.title, "Test Todo")
        XCTAssertFalse(action.oldRecord.isCompleted)
        XCTAssertNotNil(action.commitTimestamp)
    }

    func testDeleteActionDecoding() throws {
        let json = """
        {
            "type": "DELETE",
            "schema": "public",
            "table": "todos",
            "old_record": {
                "id": "todo-123",
                "title": "Deleted Todo",
                "is_completed": true,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T12:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(DeleteAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.type, "DELETE")
        XCTAssertEqual(action.schema, "public")
        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.oldRecord.id, "todo-123")
        XCTAssertEqual(action.oldRecord.title, "Deleted Todo")
        XCTAssertTrue(action.oldRecord.isCompleted)
        XCTAssertNotNil(action.commitTimestamp)
    }

    func testSelectActionDecoding() throws {
        let json = """
        {
            "type": "SELECT",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "Selected Todo",
                "is_completed": false,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T13:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(SelectAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.type, "SELECT")
        XCTAssertEqual(action.schema, "public")
        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.record.title, "Selected Todo")
        XCTAssertNotNil(action.commitTimestamp)
    }

    // MARK: - AnyAction Tests

    func testAnyActionInsertDecoding() throws {
        let json = """
        {
            "type": "INSERT",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "New Todo",
                "is_completed": false,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T14:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(AnyAction<TestTodo>.self, from: data)

        if case .insert(let insertAction) = action {
            XCTAssertEqual(insertAction.record.title, "New Todo")
            XCTAssertFalse(insertAction.record.isCompleted)
        } else {
            XCTFail("Expected insert action")
        }
    }

    func testAnyActionUpdateDecoding() throws {
        let json = """
        {
            "type": "UPDATE",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "Updated",
                "is_completed": true,
                "user_id": "user-456"
            },
            "old_record": {
                "id": "todo-123",
                "title": "Old",
                "is_completed": false,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T15:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(AnyAction<TestTodo>.self, from: data)

        if case .update(let updateAction) = action {
            XCTAssertEqual(updateAction.record.title, "Updated")
            XCTAssertEqual(updateAction.oldRecord.title, "Old")
            XCTAssertTrue(updateAction.record.isCompleted)
            XCTAssertFalse(updateAction.oldRecord.isCompleted)
        } else {
            XCTFail("Expected update action")
        }
    }

    func testAnyActionDeleteDecoding() throws {
        let json = """
        {
            "type": "DELETE",
            "schema": "public",
            "table": "todos",
            "old_record": {
                "id": "todo-123",
                "title": "Deleted",
                "is_completed": true,
                "user_id": "user-456"
            },
            "commit_timestamp": "2025-12-28T16:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(AnyAction<TestTodo>.self, from: data)

        if case .delete(let deleteAction) = action {
            XCTAssertEqual(deleteAction.oldRecord.title, "Deleted")
            XCTAssertTrue(deleteAction.oldRecord.isCompleted)
        } else {
            XCTFail("Expected delete action")
        }
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

    // MARK: - RealtimeChannel Tests

    func testChannelCreation() async {
        let client = InsForgeClient(
            insForgeURL: URL(string: "http://localhost:3000")!,
            apiKey: "test-key"
        )

        let channel1 = await client.realtime.channel("test-channel")
        XCTAssertNotNil(channel1)

        let channel2 = await client.realtime.channel("test-channel")
        XCTAssertNotNil(channel2)
        // Should return the same instance
    }

    func testMultipleChannels() async {
        let client = InsForgeClient(
            insForgeURL: URL(string: "http://localhost:3000")!,
            apiKey: "test-key"
        )

        let channel1 = await client.realtime.channel("channel-1")
        let channel2 = await client.realtime.channel("channel-2")
        let channel3 = await client.realtime.channel("channel-3")

        XCTAssertNotNil(channel1)
        XCTAssertNotNil(channel2)
        XCTAssertNotNil(channel3)
    }

    // MARK: - Schema Change Tests

    func testSchemaLevelChange() throws {
        // Test that schema-level changes can be decoded
        let json = """
        {
            "type": "INSERT",
            "schema": "public",
            "table": "users",
            "record": {
                "id": "user-789",
                "title": "New User",
                "is_completed": false,
                "user_id": "admin"
            },
            "commit_timestamp": "2025-12-28T17:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let action = try decoder.decode(InsertAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.schema, "public")
        XCTAssertEqual(action.table, "users")
        XCTAssertEqual(action.record.id, "user-789")
    }

    // MARK: - Table Change Tests

    func testTableLevelInsert() throws {
        let json = """
        {
            "type": "INSERT",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-new",
                "title": "Fresh Todo",
                "is_completed": false,
                "user_id": "user-999"
            },
            "commit_timestamp": "2025-12-28T18:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let action = try JSONDecoder().decode(InsertAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.record.title, "Fresh Todo")
    }

    func testTableLevelUpdate() throws {
        let json = """
        {
            "type": "UPDATE",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-update",
                "title": "Modified Todo",
                "is_completed": true,
                "user_id": "user-999"
            },
            "old_record": {
                "id": "todo-update",
                "title": "Original Todo",
                "is_completed": false,
                "user_id": "user-999"
            },
            "commit_timestamp": "2025-12-28T19:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let action = try JSONDecoder().decode(UpdateAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.record.title, "Modified Todo")
        XCTAssertEqual(action.oldRecord.title, "Original Todo")
    }

    func testTableLevelDelete() throws {
        let json = """
        {
            "type": "DELETE",
            "schema": "public",
            "table": "todos",
            "old_record": {
                "id": "todo-delete",
                "title": "Removed Todo",
                "is_completed": false,
                "user_id": "user-999"
            },
            "commit_timestamp": "2025-12-28T20:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let action = try JSONDecoder().decode(DeleteAction<TestTodo>.self, from: data)

        XCTAssertEqual(action.table, "todos")
        XCTAssertEqual(action.oldRecord.title, "Removed Todo")
    }

    // MARK: - Error Handling Tests

    func testInvalidActionTypeDecoding() {
        let json = """
        {
            "type": "INVALID",
            "schema": "public",
            "table": "todos",
            "record": {
                "id": "todo-123",
                "title": "Test",
                "is_completed": false,
                "user_id": "user-456"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(AnyAction<TestTodo>.self, from: data)) { error in
            if case DecodingError.dataCorrupted = error {
                // Expected error
            } else {
                XCTFail("Expected DecodingError.dataCorrupted")
            }
        }
    }

    func testMissingRequiredFields() {
        let json = """
        {
            "type": "INSERT",
            "schema": "public"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(InsertAction<TestTodo>.self, from: data))
    }

    // MARK: - Encoding Tests

    func testInsertActionEncoding() throws {
        let todo = TestTodo(
            id: "todo-encode",
            title: "Encode Test",
            isCompleted: false,
            userId: "user-encode"
        )

        let action = InsertAction(
            schema: "public",
            table: "todos",
            record: todo,
            commitTimestamp: "2025-12-28T21:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "INSERT")
        XCTAssertEqual(json?["schema"] as? String, "public")
        XCTAssertEqual(json?["table"] as? String, "todos")
        XCTAssertNotNil(json?["record"])
    }

    func testUpdateActionEncoding() throws {
        let oldTodo = TestTodo(id: "todo-1", title: "Old", isCompleted: false, userId: "user-1")
        let newTodo = TestTodo(id: "todo-1", title: "New", isCompleted: true, userId: "user-1")

        let action = UpdateAction(
            schema: "public",
            table: "todos",
            record: newTodo,
            oldRecord: oldTodo,
            commitTimestamp: "2025-12-28T22:00:00Z"
        )

        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "UPDATE")
        XCTAssertNotNil(json?["record"])
        XCTAssertNotNil(json?["old_record"])
    }
}
