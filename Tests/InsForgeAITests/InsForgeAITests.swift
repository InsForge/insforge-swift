import XCTest
@testable import InsForgeAI
@testable import InsForgeCore

final class InsForgeAITests: XCTestCase {
    func testChatMessageCreation() {
        let message = ChatMessage(role: .user, content: "Hello, AI!")

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello, AI!")

        let dict = message.toDictionary()
        XCTAssertEqual(dict["role"], "user")
        XCTAssertEqual(dict["content"], "Hello, AI!")
    }

    func testChatMessageRoles() {
        let userMessage = ChatMessage(role: .user, content: "Question")
        let assistantMessage = ChatMessage(role: .assistant, content: "Answer")
        let systemMessage = ChatMessage(role: .system, content: "Context")

        XCTAssertEqual(userMessage.role.rawValue, "user")
        XCTAssertEqual(assistantMessage.role.rawValue, "assistant")
        XCTAssertEqual(systemMessage.role.rawValue, "system")
    }
}
