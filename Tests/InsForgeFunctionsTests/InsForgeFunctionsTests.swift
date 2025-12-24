import XCTest
@testable import InsForgeFunctions
@testable import InsForgeCore

final class InsForgeFunctionsTests: XCTestCase {
    func testFunctionsClientInitialization() {
        let url = URL(string: "http://localhost/functions")!
        let client = FunctionsClient(
            url: url,
            headers: ["Authorization": "Bearer test"],
            logger: nil
        )

        XCTAssertNotNil(client)
    }
}
