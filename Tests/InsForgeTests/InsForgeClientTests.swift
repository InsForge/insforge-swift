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
                realtime: .init(
                    reconnect: .init(
                        initialDelay: 2,
                        multiplier: 1.5,
                        maxDelay: 15,
                        maxAttempts: 3,
                        jitterFactor: 0.1
                    ),
                    connectionTimeout: 5
                ),
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
        XCTAssertEqual(customClient.options.realtime.connectionTimeout, 5)
        XCTAssertEqual(customClient.options.realtime.reconnect.maxAttempts, 3)
        XCTAssertEqual(customClient.options.realtime.reconnect.initialDelay, 2, accuracy: 0.0001)
    }

    func testRealtimeOptionsDefaults() {
        XCTAssertEqual(client.options.realtime.connectionTimeout, 10, accuracy: 0.0001)
        XCTAssertEqual(client.options.realtime.reconnect.initialDelay, 1, accuracy: 0.0001)
        XCTAssertEqual(client.options.realtime.reconnect.multiplier, 2, accuracy: 0.0001)
        XCTAssertEqual(client.options.realtime.reconnect.maxDelay, 30, accuracy: 0.0001)
        XCTAssertEqual(client.options.realtime.reconnect.maxAttempts, 8)
        XCTAssertEqual(client.options.realtime.reconnect.jitterFactor, 0.2, accuracy: 0.0001)
    }
}
