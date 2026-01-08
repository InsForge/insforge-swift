import Foundation
import InsForgeCore

/// Configuration options for the database client.
///
/// Allows customization of JSON encoding and decoding behavior.
public struct DatabaseOptions: Sendable {
    /// The JSON encoder used for serializing requests.
    public let encoder: JSONEncoder
    /// The JSON decoder used for deserializing responses.
    public let decoder: JSONDecoder

    /// Creates database options with custom or default encoders.
    /// - Parameters:
    ///   - encoder: Optional custom JSON encoder. Defaults to ISO 8601 date encoding.
    ///   - decoder: Optional custom JSON decoder. Defaults to ISO 8601 date decoding with fractional seconds.
    public init(
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        // Default encoder with ISO 8601 date encoding
        if let encoder = encoder {
            self.encoder = encoder
        } else {
            let defaultEncoder = JSONEncoder()
            defaultEncoder.dateEncodingStrategy = .iso8601
            self.encoder = defaultEncoder
        }

        // Default decoder with ISO 8601 date decoding (supports fractional seconds)
        if let decoder = decoder {
            self.decoder = decoder
        } else {
            let defaultDecoder = JSONDecoder()
            defaultDecoder.dateDecodingStrategy = iso8601WithFractionalSecondsDecodingStrategy()
            self.decoder = defaultDecoder
        }
    }
}

/// Database client for PostgREST-style operations.
///
/// Provides a fluent API for querying and manipulating data in PostgreSQL databases
/// through the InsForge API.
public actor DatabaseClient {
    private let url: URL
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: (any InsForgeLogger)?

    /// Creates a new database client.
    /// - Parameters:
    ///   - url: The base URL of the database API.
    ///   - headersProvider: A thread-safe provider for HTTP headers.
    ///   - options: Optional database configuration options.
    ///   - logger: An optional logger for debugging.
    public init(
        url: URL,
        headersProvider: LockIsolated<[String: String]>,
        options: DatabaseOptions = DatabaseOptions(),
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = HTTPClient(logger: logger)
        self.encoder = options.encoder
        self.decoder = options.decoder
        self.logger = logger
    }

    /// Creates a query builder for the specified table.
    /// - Parameter table: The name of the table to query.
    /// - Returns: A `QueryBuilder` for constructing queries.
    public func from(_ table: String) -> QueryBuilder {
        QueryBuilder(
            url: url.appendingPathComponent("records").appendingPathComponent(table),
            headersProvider: headersProvider,
            httpClient: httpClient,
            encoder: encoder,
            decoder: decoder
        )
    }
}

/// Query builder for database operations.
///
/// Provides a fluent interface for constructing and executing database queries.
/// Supports filtering, ordering, pagination, and CRUD operations.
public struct QueryBuilder: Sendable {
    private let url: URL
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var queryItems: [URLQueryItem] = []
    private var preferHeader: String?

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    init(
        url: URL,
        headersProvider: LockIsolated<[String: String]>,
        httpClient: HTTPClient,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = httpClient
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Query Modifiers

    /// Selects specific columns to return.
    /// - Parameter columns: Comma-separated column names, or "*" for all columns.
    /// - Returns: A new `QueryBuilder` with the select clause applied.
    public func select(_ columns: String = "*") -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "select", value: columns))
        return builder
    }

    /// Filters by equality.
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The value to match.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func eq(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "eq.\(value)"))
        return builder
    }

    /// Filters by inequality (not equal).
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The value to exclude.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func neq(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "neq.\(value)"))
        return builder
    }

    /// Filters by greater than comparison.
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The threshold value.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func gt(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "gt.\(value)"))
        return builder
    }

    /// Filters by greater than or equal comparison.
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The threshold value.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func gte(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "gte.\(value)"))
        return builder
    }

    /// Filters by less than comparison.
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The threshold value.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func lt(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "lt.\(value)"))
        return builder
    }

    /// Filters by less than or equal comparison.
    /// - Parameters:
    ///   - column: The column name to filter on.
    ///   - value: The threshold value.
    /// - Returns: A new `QueryBuilder` with the filter applied.
    public func lte(_ column: String, value: Any) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "lte.\(value)"))
        return builder
    }

    /// Orders results by a column.
    /// - Parameters:
    ///   - column: The column name to order by.
    ///   - ascending: Whether to sort ascending. Defaults to `true`.
    /// - Returns: A new `QueryBuilder` with ordering applied.
    public func order(_ column: String, ascending: Bool = true) -> QueryBuilder {
        var builder = self
        let direction = ascending ? "asc" : "desc"
        builder.queryItems.append(URLQueryItem(name: "order", value: "\(column).\(direction)"))
        return builder
    }

    /// Limits the number of results returned.
    /// - Parameter count: The maximum number of results.
    /// - Returns: A new `QueryBuilder` with the limit applied.
    public func limit(_ count: Int) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "limit", value: "\(count)"))
        return builder
    }

    /// Offsets results for pagination.
    /// - Parameter count: The number of results to skip.
    /// - Returns: A new `QueryBuilder` with the offset applied.
    public func offset(_ count: Int) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "offset", value: "\(count)"))
        return builder
    }

    /// Applies range-based pagination (from and to are inclusive).
    /// - Parameters:
    ///   - from: Starting index (0-based).
    ///   - to: Ending index (inclusive).
    /// - Returns: A new `QueryBuilder` with range applied.
    public func range(from: Int, to: Int) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: "offset", value: "\(from)"))
        builder.queryItems.append(URLQueryItem(name: "limit", value: "\(to - from + 1)"))
        return builder
    }

    /// Filters by pattern matching (case-sensitive).
    /// - Parameters:
    ///   - column: Column name to filter.
    ///   - pattern: Pattern to match (use % as wildcard).
    /// - Returns: A new `QueryBuilder` with like filter.
    public func like(_ column: String, pattern: String) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "like.\(pattern)"))
        return builder
    }

    /// Filters by pattern matching (case-insensitive).
    /// - Parameters:
    ///   - column: Column name to filter.
    ///   - pattern: Pattern to match (use % as wildcard).
    /// - Returns: A new `QueryBuilder` with ilike filter.
    public func ilike(_ column: String, pattern: String) -> QueryBuilder {
        var builder = self
        builder.queryItems.append(URLQueryItem(name: column, value: "ilike.\(pattern)"))
        return builder
    }

    /// Filters where column value is in an array.
    /// - Parameters:
    ///   - column: Column name to filter.
    ///   - values: Array of values to match.
    /// - Returns: A new `QueryBuilder` with in filter.
    public func `in`(_ column: String, values: [Any]) -> QueryBuilder {
        var builder = self
        let valueString = values.map { "\($0)" }.joined(separator: ",")
        builder.queryItems.append(URLQueryItem(name: column, value: "in.(\(valueString))"))
        return builder
    }

    /// Filters for null/boolean checks.
    /// - Parameters:
    ///   - column: Column name to filter.
    ///   - value: Value to check (null if nil, or true/false).
    /// - Returns: A new `QueryBuilder` with is filter.
    public func `is`(_ column: String, value: Bool?) -> QueryBuilder {
        var builder = self
        let valueString: String
        if let boolValue = value {
            valueString = boolValue ? "true" : "false"
        } else {
            valueString = "null"
        }
        builder.queryItems.append(URLQueryItem(name: column, value: "is.\(valueString)"))
        return builder
    }

    // MARK: - Execute

    /// Executes a SELECT query and returns decoded results.
    /// - Returns: An array of decoded objects.
    /// - Throws: `InsForgeError` if the query fails.
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

    /// Inserts multiple records into the table.
    /// - Parameter values: An array of records to insert.
    /// - Returns: The inserted records with server-generated fields populated.
    /// - Throws: `InsForgeError` if the insert fails.
    public func insert<T: Encodable>(_ values: [T]) async throws -> [T] where T: Decodable {
        var builder = self
        builder.preferHeader = "return=representation"

        let data = try builder.encoder.encode(values)

        var requestHeaders = builder.headers
        requestHeaders["Content-Type"] = "application/json"
        if let prefer = builder.preferHeader {
            requestHeaders["Prefer"] = prefer
        }

        let response = try await builder.httpClient.execute(
            .post,
            url: builder.url,
            headers: requestHeaders,
            body: data
        )

        return try builder.decoder.decode([T].self, from: response.data)
    }

    /// Inserts a single record into the table.
    /// - Parameter value: The record to insert.
    /// - Returns: The inserted record with server-generated fields populated.
    /// - Throws: `InsForgeError` if the insert fails.
    public func insert<T: Encodable>(_ value: T) async throws -> T where T: Decodable {
        let results: [T] = try await insert([value])
        guard let first = results.first else {
            throw InsForgeError.unknown("Insert failed")
        }
        return first
    }

    // MARK: - Update

    /// Updates records matching the current filters.
    /// - Parameter values: The values to update.
    /// - Returns: The updated records.
    /// - Throws: `InsForgeError` if the update fails.
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

    /// Deletes records matching the current filters.
    /// - Throws: `InsForgeError` if the delete fails.
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
