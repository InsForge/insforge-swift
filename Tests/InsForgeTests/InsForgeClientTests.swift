import XCTest
@testable import InsForge

final class InsForgeClientTests: XCTestCase {
    var client: InsForgeClient!
    var insforgeHost = "https://pg6afqz9.us-east.insforge.app"
    var insforgeApiKey = "ik_ca177fcf1e2e72e8d1e0c2c23dbe3b79"

    override func setUp() async throws {
        client = InsForgeClient(
            insForgeURL: URL(string: insforgeHost)!,
            apiKey: insforgeApiKey
        )
    }

    override func tearDown() async throws {
        client = nil
    }

    func testClientInitialization() {
        XCTAssertEqual(client.insForgeURL.absoluteString, insforgeHost)
        XCTAssertEqual(client.apiKey, insforgeApiKey)
        // Headers are private, just verify client was created
        XCTAssertNotNil(client)
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
            insForgeURL: URL(string: insforgeHost)!,
            apiKey: insforgeApiKey,
            options: InsForgeClientOptions(
                global: .init(
                    headers: ["X-Custom": "value"],
                    logger: nil
                )
            )
        )

        // Just verify client was created with custom options
        XCTAssertNotNil(customClient)
        XCTAssertEqual(customClient.options.global.headers["X-Custom"], "value")
    }
}
