import XCTest
import Logging
import TestHelper
@testable import InsForge

final class InsForgeClientTests: XCTestCase {
    var client: InsForgeClient!

    override func setUp() async throws {
        client = TestHelper.createClient()
    }

    override func tearDown() async throws {
        client = nil
    }

    func testClientInitialization() {
        XCTAssertEqual(client.baseURL.absoluteString, TestHelper.insForgeURL)
        XCTAssertEqual(client.anonKey, TestHelper.anonKey)
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
        let customClient = TestHelper.createClient(
            options: InsForgeClientOptions(
                global: .init(
                    headers: ["X-Custom": "value"],
                    logLevel: .debug,
                    logDestination: .console
                )
            )
        )

        // Just verify client was created with custom options
        XCTAssertNotNil(customClient)
        XCTAssertEqual(customClient.options.global.headers["X-Custom"], "value")
        XCTAssertEqual(customClient.options.global.logLevel, .debug)
    }
}
