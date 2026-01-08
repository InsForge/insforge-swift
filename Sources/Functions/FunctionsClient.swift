import Foundation
import InsForgeCore
import Logging

/// Functions client for invoking serverless functions
public actor FunctionsClient {
    private let url: URL
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    public init(
        url: URL,
        headersProvider: LockIsolated<[String: String]>
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = HTTPClient()
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

        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let requestBody = requestBody, let bodyString = String(data: requestBody, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: requestBody
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

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

        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: requestBody, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: requestBody
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

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

        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let requestBody = requestBody, let bodyString = String(data: requestBody, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: requestBody
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8), !responseString.isEmpty {
            logger.trace("Response body: \(responseString)")
        }
    }
}
