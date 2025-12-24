import XCTest
@testable import InsForgeRealtime
@testable import InsForgeCore

final class InsForgeRealtimeTests: XCTestCase {
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
}
