import XCTest
@testable import InsForge

final class InsForgeClientTests: XCTestCase {
    var client: InsForgeClient!

    override func setUp() async throws {
        client = InsForgeClient(
            insForgeURL: URL(string: "https://test.insforge.com")!,
            apiKey: "test-key"
        )
    }

    override func tearDown() async throws {
        client = nil
    }

    func testClientInitialization() {
        XCTAssertEqual(client.insForgeURL.absoluteString, "https://test.insforge.com")
        XCTAssertEqual(client.apiKey, "test-key")
        XCTAssertEqual(client.headers["apikey"], "test-key")
        XCTAssertEqual(client.headers["Authorization"], "Bearer test-key")
    }

    func testSubClientsInitialization() {
        // All sub-clients should be lazily initialized
        XCTAssertNotNil(client.auth)
        XCTAssertNotNil(client.database)
        XCTAssertNotNil(client.storage)
        XCTAssertNotNil(client.functions)
        XCTAssertNotNil(client.ai)
        XCTAssertNotNil(client.realtime)
    }

    func testCustomOptions() {
        let customClient = InsForgeClient(
            insForgeURL: URL(string: "https://test.insforge.com")!,
            apiKey: "test-key",
            options: InsForgeClientOptions(
                global: .init(
                    headers: ["X-Custom": "value"],
                    logger: ConsoleLogger()
                )
            )
        )

        XCTAssertEqual(customClient.headers["X-Custom"], "value")
    }
}
