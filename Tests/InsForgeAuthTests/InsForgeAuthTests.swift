import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

final class InsForgeAuthTests: XCTestCase {
    func testUserDecodingFromJSON() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "email": "test@example.com",
            "emailVerified": true,
            "providers": ["email"],
            "createdAt": "2025-01-01T00:00:00Z",
            "updatedAt": "2025-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertTrue(user.emailVerified)
        XCTAssertEqual(user.providers, ["email"])
    }

    func testOAuthProviderCases() {
        let providers = OAuthProvider.allCases
        XCTAssertTrue(providers.contains(.google))
        XCTAssertTrue(providers.contains(.github))
        XCTAssertTrue(providers.contains(.apple))
        XCTAssertEqual(providers.count, 11)
    }
}
