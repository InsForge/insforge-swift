import Foundation
import InsForgeCore

/// Functions client for invoking serverless functions
public actor FunctionsClient {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let logger: (any InsForgeLogger)?

    public init(
        url: URL,
        headers: [String: String],
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.logger = logger
    }

    /// Invoke a function
    public func invoke<T: Decodable>(
        _ slug: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let endpoint = url.appendingPathComponent(slug)

        var requestBody: Data?
        if let body = body {
            requestBody = try JSONSerialization.data(withJSONObject: body)
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: requestBody
        )

        return try response.decode(T.self)
    }

    /// Invoke a function with Encodable body
    public func invoke<I: Encodable, O: Decodable>(
        _ slug: String,
        body: I
    ) async throws -> O {
        let endpoint = url.appendingPathComponent(slug)

        let encoder = JSONEncoder()
        let requestBody = try encoder.encode(body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: requestBody
        )

        let decoder = JSONDecoder()
        return try decoder.decode(O.self, from: response.data)
    }

    /// Invoke a function without expecting a response body
    public func invoke(_ slug: String, body: [String: Any]? = nil) async throws {
        let endpoint = url.appendingPathComponent(slug)

        var requestBody: Data?
        if let body = body {
            requestBody = try JSONSerialization.data(withJSONObject: body)
        }

        _ = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: requestBody
        )

        logger?.log("Function '\(slug)' invoked")
    }
}
