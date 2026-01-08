import XCTest
@testable import InsForge
@testable import InsForgeDatabase
@testable import InsForgeCore

// MARK: - Test Models

struct Post: Codable, Equatable {
    let id: String?
    var title: String
    var content: String
    var published: Bool
    var views: Int
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case published
        case views
        case createdAt = "created_at"
    }
}

struct User: Codable, Equatable {
    let id: String?
    var email: String
    var name: String
    var age: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case age
    }
}

// MARK: - Tests

final class InsForgeDatabaseTests: XCTestCase {
    // MARK: - Setup

    private func createTestClient() -> InsForgeClient {
        return InsForgeClient(
            baseURL: URL(string: "https://pg6afqz9.us-east.insforge.app")!,
            anonKey: "ik_ca177fcf1e2e72e8d1e0c2c23dbe3b79"
        )
    }

    // MARK: - Query Builder Tests

    func testQueryBuilderSelectModifier() async {
        let client = createTestClient()
        let builder = await client.database.from("posts")

        let modifiedBuilder = builder.select("id,title,content")

        // Query builder should be immutable and return new instance
        XCTAssertNotNil(modifiedBuilder)
    }

    func testQueryBuilderFilterChaining() async {
        let client = createTestClient()
        let builder = await client.database.from("posts")

        let filtered = builder
            .eq("published", value: true)
            .gt("views", value: 100)
            .order("createdAt", ascending: false)
            .limit(10)

        XCTAssertNotNil(filtered)
    }

    // MARK: - Filter Operators Tests

    func testQueryBuilderMultipleFilters() async {
        let client = createTestClient()
        let builder = await client.database.from("users")

        let filtered = builder
            .select("id,name,email")
            .eq("active", value: true)
            .gte("age", value: 18)
            .lte("age", value: 65)
            .order("name", ascending: true)
            .limit(20)
            .offset(10)

        XCTAssertNotNil(filtered)
    }

    func testQueryBuilderComparisonOperators() async {
        let client = createTestClient()
        let builder = await client.database.from("posts")

        // Test all comparison operators
        let eqBuilder = builder.eq("status", value: "published")
        XCTAssertNotNil(eqBuilder)

        let neqBuilder = builder.neq("status", value: "draft")
        XCTAssertNotNil(neqBuilder)

        let gtBuilder = builder.gt("views", value: 100)
        XCTAssertNotNil(gtBuilder)

        let gteBuilder = builder.gte("views", value: 100)
        XCTAssertNotNil(gteBuilder)

        let ltBuilder = builder.lt("views", value: 1000)
        XCTAssertNotNil(ltBuilder)

        let lteBuilder = builder.lte("views", value: 1000)
        XCTAssertNotNil(lteBuilder)
    }

    func testQueryBuilderPagination() async {
        let client = createTestClient()
        let builder = await client.database.from("posts")

        // First page
        let page1 = builder.limit(10).offset(0)
        XCTAssertNotNil(page1)

        // Second page
        let page2 = builder.limit(10).offset(10)
        XCTAssertNotNil(page2)

        // Third page
        let page3 = builder.limit(10).offset(20)
        XCTAssertNotNil(page3)
    }

    // MARK: - Model Encoding Tests

    func testPostModelEncoding() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let post = Post(
            id: "123",
            title: "Test Post",
            content: "This is a test post content",
            published: true,
            views: 42,
            createdAt: Date()
        )

        let data = try encoder.encode(post)
        XCTAssertNotNil(data)

        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["id"] as? String, "123")
        XCTAssertEqual(json?["title"] as? String, "Test Post")
        XCTAssertEqual(json?["content"] as? String, "This is a test post content")
        XCTAssertEqual(json?["published"] as? Bool, true)
        XCTAssertEqual(json?["views"] as? Int, 42)
    }

    func testUserModelEncoding() throws {
        let encoder = JSONEncoder()

        let user = User(
            id: "user-123",
            email: "test@example.com",
            name: "Test User",
            age: 25
        )

        let data = try encoder.encode(user)
        XCTAssertNotNil(data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["id"] as? String, "user-123")
        XCTAssertEqual(json?["email"] as? String, "test@example.com")
        XCTAssertEqual(json?["name"] as? String, "Test User")
        XCTAssertEqual(json?["age"] as? Int, 25)
    }

    func testMultiplePostsEncoding() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let posts = [
            Post(id: "1", title: "Post 1", content: "Content 1", published: true, views: 10, createdAt: Date()),
            Post(id: "2", title: "Post 2", content: "Content 2", published: false, views: 20, createdAt: Date()),
            Post(id: "3", title: "Post 3", content: "Content 3", published: true, views: 30, createdAt: Date())
        ]

        let data = try encoder.encode(posts)
        XCTAssertNotNil(data)

        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(jsonArray?.count, 3)
        XCTAssertEqual(jsonArray?[0]["title"] as? String, "Post 1")
        XCTAssertEqual(jsonArray?[1]["title"] as? String, "Post 2")
        XCTAssertEqual(jsonArray?[2]["title"] as? String, "Post 3")
    }

    // MARK: - Model Decoding Tests

    func testPostModelDecoding() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let jsonString = """
        {
            "id": "456",
            "title": "Decoded Post",
            "content": "This post was decoded from JSON",
            "published": false,
            "views": 100,
            "created_at": "2025-12-27T12:00:00Z"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let post = try decoder.decode(Post.self, from: data)

        XCTAssertEqual(post.id, "456")
        XCTAssertEqual(post.title, "Decoded Post")
        XCTAssertEqual(post.content, "This post was decoded from JSON")
        XCTAssertEqual(post.published, false)
        XCTAssertEqual(post.views, 100)
        XCTAssertNotNil(post.createdAt)
    }

    func testUserModelDecoding() throws {
        let decoder = JSONDecoder()

        let jsonString = """
        {
            "id": "user-456",
            "email": "john@example.com",
            "name": "John Doe",
            "age": 30
        }
        """

        let data = jsonString.data(using: .utf8)!
        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.id, "user-456")
        XCTAssertEqual(user.email, "john@example.com")
        XCTAssertEqual(user.name, "John Doe")
        XCTAssertEqual(user.age, 30)
    }

    func testMultiplePostsDecoding() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let jsonString = """
        [
            {
                "id": "1",
                "title": "First Post",
                "content": "First content",
                "published": true,
                "views": 100,
                "created_at": "2025-12-27T10:00:00Z"
            },
            {
                "id": "2",
                "title": "Second Post",
                "content": "Second content",
                "published": true,
                "views": 200,
                "created_at": "2025-12-27T11:00:00Z"
            }
        ]
        """

        let data = jsonString.data(using: .utf8)!
        let posts = try decoder.decode([Post].self, from: data)

        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts[0].title, "First Post")
        XCTAssertEqual(posts[0].views, 100)
        XCTAssertEqual(posts[1].title, "Second Post")
        XCTAssertEqual(posts[1].views, 200)
    }

    // MARK: - Edge Cases Tests

    func testOptionalFieldsHandling() throws {
        let decoder = JSONDecoder()

        // User without optional age field
        let jsonString = """
        {
            "id": "user-789",
            "email": "optional@example.com",
            "name": "Optional User"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.id, "user-789")
        XCTAssertEqual(user.email, "optional@example.com")
        XCTAssertEqual(user.name, "Optional User")
        XCTAssertNil(user.age)
    }

    func testEmptyArrayDecoding() throws {
        let decoder = JSONDecoder()

        let jsonString = "[]"
        let data = jsonString.data(using: .utf8)!
        let posts = try decoder.decode([Post].self, from: data)

        XCTAssertEqual(posts.count, 0)
        XCTAssertTrue(posts.isEmpty)
    }

    func testSnakeCaseToCamelCaseMapping() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Test that snake_case JSON keys map to camelCase properties
        let jsonString = """
        {
            "id": "post-123",
            "title": "Snake Case Test",
            "content": "Testing snake_case mapping",
            "published": true,
            "views": 50,
            "created_at": "2025-12-27T12:00:00Z"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let post = try decoder.decode(Post.self, from: data)

        XCTAssertNotNil(post.createdAt)
        XCTAssertEqual(post.id, "post-123")
    }

    // MARK: - DatabaseClient Tests

    func testDatabaseClientFromTable() async {
        let client = createTestClient()
        let builder = await client.database.from("posts")
        XCTAssertNotNil(builder)
    }

    func testDatabaseClientMultipleTables() async {
        let client = createTestClient()

        let postsBuilder = await client.database.from("posts")
        XCTAssertNotNil(postsBuilder)

        let usersBuilder = await client.database.from("users")
        XCTAssertNotNil(usersBuilder)

        let commentsBuilder = await client.database.from("comments")
        XCTAssertNotNil(commentsBuilder)
    }

    func testDatabaseOptionsDefaults() {
        let options = DatabaseOptions()

        XCTAssertNotNil(options.encoder)
        XCTAssertNotNil(options.decoder)
    }

    func testDatabaseOptionsCustom() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let options = DatabaseOptions(encoder: encoder, decoder: decoder)

        XCTAssertNotNil(options.encoder)
        XCTAssertNotNil(options.decoder)
    }
}
