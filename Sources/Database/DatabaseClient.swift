import Foundation
import InsForgeCore

/// Database client for PostgREST-style operations
public actor DatabaseClient {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: (any InsForgeLogger)?

    public init(
        url: URL,
        headers: [String: String],
        options: InsForgeClientOptions.DatabaseOptions,
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.encoder = options.encoder
        self.decoder = options.decoder
        self.logger = logger
    }

    /// Create a query builder for a table
    public func from(_ table: String) -> QueryBuilder {
        QueryBuilder(
            url: url.appendingPathComponent("records").appendingPathComponent(table),
            headers: headers,
            httpClient: httpClient,
            encoder: encoder,
            decoder: decoder
        )
    }
}

/// Query builder for database operations
public struct QueryBuilder: Sendable {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var queryItems: [URLQueryItem] = []
    private var preferHeader: String?

    init(
        url: URL,
        headers: [String: String],
        httpClient: HTTPClient,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = httpClient
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Query Modifiers

    /// Select specific columns
    public func select(_ columns: String = "*") -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "select", value: columns))
        return builder
    }

    /// Filter by equality
    public func eq(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "eq.\(value)"))
        return builder
    }

    /// Filter by not equal
    public func neq(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "neq.\(value)"))
        return builder
    }

    /// Filter by greater than
    public func gt(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "gt.\(value)"))
        return builder
    }

    /// Filter by greater than or equal
    public func gte(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "gte.\(value)"))
        return builder
    }

    /// Filter by less than
    public func lt(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "lt.\(value)"))
        return builder
    }

    /// Filter by less than or equal
    public func lte(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "lte.\(value)"))
        return builder
    }

    /// Order results
    public func order(_ column: String, ascending: Bool = true) -> QueryBuilder {
        var builder = self
        let direction = ascending ? "asc" : "desc"
        builder.queryItems.append(URLQueryItem(name: "order", value: "\(column).\(direction)"))
        return builder
    }

    /// Limit number of results
    public func limit(_ count: Int) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "limit", value: "\(count)"))
        return builder
    }

    /// Offset results for pagination
    public func offset(_ count: Int) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "offset", value: "\(count)"))
        return builder
    }

    // MARK: - Execute

    /// Execute SELECT query
    public func execute<T: Decodable>() async throws -> [T] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let requestURL = components?.url else {
            throw InsForgeError.invalidURL
        }

        let response = try await httpClient.execute(
            .get,
            url: requestURL,
            headers: headers
        )

        return try decoder.decode([T].self, from: response.data)
    }

    // MARK: - Insert

    /// Insert records
    public func insert<T: Encodable>(_ values: [T]) async throws -> [T] where T: Decodable {
        var builder = self
        builder.preferHeader = "return=representation"

        let data = try encoder.encode(values)

        var requestHeaders = headers
        requestHeaders["Content-Type"] = "application/json"
        if let prefer = preferHeader {
            requestHeaders["Prefer"] = prefer
        }

        let response = try await httpClient.execute(
            .post,
            url: url,
            headers: requestHeaders,
            body: data
        )

        return try decoder.decode([T].self, from: response.data)
    }

    /// Insert single record
    public func insert<T: Encodable>(_ value: T) async throws -> T where T: Decodable {
        let results: [T] = try await insert([value])
        guard let first = results.first else {
            throw InsForgeError.unknown("Insert failed")
        }
        return first
    }

    // MARK: - Update

    /// Update records
    public func update<T: Encodable>(_ values: T) async throws -> [T] where T: Decodable {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let requestURL = components?.url else {
            throw InsForgeError.invalidURL
        }

        let data = try encoder.encode(values)

        var requestHeaders = headers
        requestHeaders["Content-Type"] = "application/json"
        requestHeaders["Prefer"] = "return=representation"

        let response = try await httpClient.execute(
            .patch,
            url: requestURL,
            headers: requestHeaders,
            body: data
        )

        return try decoder.decode([T].self, from: response.data)
    }

    // MARK: - Delete

    /// Delete records
    public func delete() async throws {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let requestURL = components?.url else {
            throw InsForgeError.invalidURL
        }

        _ = try await httpClient.execute(
            .delete,
            url: requestURL,
            headers: headers
        )
    }
}
