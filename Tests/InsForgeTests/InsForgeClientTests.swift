import XCTest
import Logging
@testable import InsForge

final class InsForgeClientTests: XCTestCase {
    var client: InsForgeClient!
    var insforgeHost = "https://pg6afqz9.us-east.insforge.app"
    var insforgeApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3OC0xMjM0LTU2NzgtOTBhYi1jZGVmMTIzNDU2NzgiLCJlbWFpbCI6ImFub25AaW5zZm9yZ2UuY29tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5MDc5MzJ9.K0semVtcacV55qeEhVUI3WKWzT7p87JU7wNzdXysRWo"

    override func setUp() async throws {
        client = InsForgeClient(
            baseURL: URL(string: insforgeHost)!,
            anonKey: insforgeApiKey
        )
    }

    override func tearDown() async throws {
        client = nil
    }

    func testClientInitialization() {
        XCTAssertEqual(client.baseURL.absoluteString, insforgeHost)
        XCTAssertEqual(client.anonKey, insforgeApiKey)
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
            baseURL: URL(string: insforgeHost)!,
            anonKey: insforgeApiKey,
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
