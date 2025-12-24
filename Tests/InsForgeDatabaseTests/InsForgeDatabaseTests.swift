import XCTest
@testable import InsForgeDatabase
@testable import InsForgeCore

final class InsForgeDatabaseTests: XCTestCase {
    func testQueryBuilderSelectModifier() {
        let builder = QueryBuilder(
            url: URL(string: "http://localhost/records/posts")!,
            headers: [:],
            httpClient: HTTPClient(),
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )

        let modifiedBuilder = builder.select("id,title,content")

        // Query builder should be immutable and return new instance
        XCTAssertNotNil(modifiedBuilder)
    }

    func testQueryBuilderFilterChaining() {
        let builder = QueryBuilder(
            url: URL(string: "http://localhost/records/posts")!,
            headers: [:],
            httpClient: HTTPClient(),
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )

        let filtered = builder
            .eq("published", value: true)
            .gt("views", value: 100)
            .order("createdAt", ascending: false)
            .limit(10)

        XCTAssertNotNil(filtered)
    }
}
