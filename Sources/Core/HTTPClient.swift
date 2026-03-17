import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Token Refresh Handler

/// Protocol for handling automatic token refresh on 401 errors.
///
/// Implement this protocol to provide automatic token refresh capability
/// when access tokens expire during API requests.
public protocol TokenRefreshHandler: Sendable {
    /// Attempts to refresh the access token.
    /// - Returns: The new access token if refresh was successful.
    /// - Throws: An error if token refresh fails (e.g., refresh token expired).
    func refreshToken() async throws -> String

    /// Returns the current access token without refreshing.
    /// - Returns: The current access token if available.
    func getCurrentToken() async -> String?
}

/// HTTP method types supported by the client.
public enum HTTPMethod: String {
    /// HTTP GET method.
    case get = "GET"
    /// HTTP POST method.
    case post = "POST"
    /// HTTP PUT method.
    case put = "PUT"
    /// HTTP PATCH method.
    case patch = "PATCH"
    /// HTTP DELETE method.
    case delete = "DELETE"
    /// HTTP HEAD method.
    case head = "HEAD"
}

// MARK: - Retry Configuration (re-exported for use inside Core)

/// Controls automatic retry behaviour. Defined in `InsForgeClientOptions`
/// and forwarded here so `HTTPClient` remains independent of the top-level module.
public struct RetryConfiguration: Sendable {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let useJitter: Bool

    public static let `default` = RetryConfiguration()
    public static let disabled = RetryConfiguration(maxRetries: 0)

    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30,
        useJitter: Bool = true
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.useJitter = useJitter
    }

    func delay(for attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        guard useJitter else { return capped }
        let jitter = Double.random(in: 0...(capped * 0.1))
        return capped + jitter
    }
}

/// Carries a 429 response's `InsForgeError` together with the parsed `Retry-After`
/// delay. Using a dedicated error type (rather than actor-stored mutable state) ensures
/// that concurrent retry loops each get their own `Retry-After` value and cannot
/// accidentally read a value written by a different concurrent request.
private struct RateLimitedError: Error {
    let insForgeError: InsForgeError
    let retryAfter: TimeInterval?
}

/// HTTP Client for making network requests.
///
/// This actor provides thread-safe HTTP request execution with support for
/// various HTTP methods, file uploads, and response decoding.
public actor HTTPClient {
    private let session: URLSession
    private let retry: RetryConfiguration
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Creates a new HTTP client.
    /// - Parameters:
    ///   - session: The URL session to use for requests. Defaults to `.shared`.
    ///   - retry: Retry configuration for transient failures. Defaults to `.default`.
    public init(session: URLSession = .shared, retry: RetryConfiguration = .default) {
        self.session = session
        self.retry = retry
    }

    // MARK: - Private Helpers

    /// Builds a `URLRequest` from the given parameters.
    private func buildRequest(
        method: HTTPMethod,
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    /// Parses the `Retry-After` header from an `HTTPURLResponse`.
    ///
    /// The header may be an integer number of seconds or an HTTP-date string.
    private func parseRetryAfter(from httpResponse: HTTPURLResponse) -> TimeInterval? {
        guard let value = httpResponse.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // Integer seconds form: "Retry-After: 30"
        if let seconds = TimeInterval(value) {
            return seconds
        }
        // HTTP-date form: "Retry-After: Wed, 21 Oct 2015 07:28:00 GMT"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    /// Performs a single `URLSession` round-trip and converts the result into
    /// an `HTTPResponse`, throwing `InsForgeError` on non-2xx status codes.
    ///
    /// For 429 responses, throws `RateLimitedError` (a private type) so that the
    /// parsed `Retry-After` value travels with the error rather than being stored as
    /// mutable actor state (which could be overwritten by a concurrent request).
    private func performRequest(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InsForgeError.invalidResponse
            }

            logger.debug("Response status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.trace("Response body: \(responseString)")
            }

            if !(200..<300).contains(httpResponse.statusCode) {
                let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                logger.error("HTTP Error: status=\(httpResponse.statusCode), message=\(errorBody?.message ?? "Request failed")")
                let insForgeError = InsForgeError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: errorBody?.message ?? "Request failed",
                    error: errorBody?.error,
                    nextActions: errorBody?.nextActions
                )
                // For 429, carry the Retry-After value through a private error wrapper
                // so that concurrent retry loops each see their own value.
                if httpResponse.statusCode == 429 {
                    throw RateLimitedError(
                        insForgeError: insForgeError,
                        retryAfter: parseRetryAfter(from: httpResponse)
                    )
                }
                throw insForgeError
            }

            return HTTPResponse(data: data, response: httpResponse)
        } catch let error as RateLimitedError {
            throw error
        } catch let error as InsForgeError {
            throw error
        } catch {
            logger.error("Network error: \(error)")
            throw InsForgeError.networkError(NetworkError.from(error))
        }
    }

    /// Returns `true` for status codes that should trigger an automatic retry.
    private func isRetryableStatusCode(_ code: Int) -> Bool {
        code == 429 || (500...599).contains(code)
    }

    /// Returns `true` for `InsForgeError` values that should trigger an automatic retry.
    private func isRetryableError(_ error: InsForgeError) -> Bool {
        switch error {
        case .httpError(let statusCode, _, _, _):
            return isRetryableStatusCode(statusCode)
        case .networkError(let networkError):
            switch networkError {
            case .timeout, .cannotConnect, .other:
                return true
            case .noNetwork, .cancelled, .sslError:
                return false
            }
        default:
            return false
        }
    }

    /// Executes `operation` with automatic retry on transient failures.
    ///
    /// - 429 responses: waits for the duration specified in `Retry-After` (or falls
    ///   back to the computed back-off delay). The delay is read from the private
    ///   `RateLimitedError` wrapper — never from shared actor state — so concurrent
    ///   requests cannot interfere with each other's retry timing.
    /// - 5xx responses / transient network errors: uses truncated exponential back-off.
    private func withRetry(
        _ operation: () async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let rateLimited as RateLimitedError {
                let error = rateLimited.insForgeError
                guard retry.maxRetries > 0,
                      attempt < retry.maxRetries,
                      isRetryableError(error) else {
                    throw error
                }
                let waitTime = rateLimited.retryAfter ?? retry.delay(for: attempt)
                logger.warning("Rate limited (429). Retrying after \(waitTime)s (attempt \(attempt + 1)/\(retry.maxRetries))…")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                attempt += 1
            } catch let error as InsForgeError {
                guard retry.maxRetries > 0,
                      attempt < retry.maxRetries,
                      isRetryableError(error) else {
                    throw error
                }
                let waitTime = retry.delay(for: attempt)
                if case .httpError(let code, _, _, _) = error {
                    logger.warning("HTTP \(code) error. Retrying in \(String(format: "%.2f", waitTime))s (attempt \(attempt + 1)/\(retry.maxRetries))…")
                } else {
                    logger.warning("Transient network error. Retrying in \(String(format: "%.2f", waitTime))s (attempt \(attempt + 1)/\(retry.maxRetries))…")
                }
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                attempt += 1
            }
        }
    }

    // MARK: - Public API

    /// Executes an HTTP request.
    /// - Parameters:
    ///   - method: The HTTP method to use.
    ///   - url: The URL to request.
    ///   - headers: Optional HTTP headers. Defaults to empty.
    ///   - body: Optional request body data. Defaults to `nil`.
    /// - Returns: An `HTTPResponse` containing the response data.
    /// - Throws: `InsForgeError` if the request fails.
    public func execute(
        _ method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        let request = buildRequest(method: method, url: url, headers: headers, body: body)

        logger.debug("[\(method.rawValue)] \(url)")
        if !headers.isEmpty {
            logger.trace("Request headers: \(headers)")
        }
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        return try await withRetry {
            try await self.performRequest(request)
        }
    }

    /// Uploads multipart form data with the specified HTTP method.
    /// - Parameters:
    ///   - url: The URL to upload to.
    ///   - method: The HTTP method to use. Defaults to `.put`.
    ///   - headers: Optional HTTP headers. Defaults to empty.
    ///   - file: The file data to upload.
    ///   - fileName: The name of the file.
    ///   - mimeType: The MIME type of the file.
    /// - Returns: An `HTTPResponse` containing the response data.
    /// - Throws: `InsForgeError` if the upload fails.
    public func upload(
        url: URL,
        method: HTTPMethod = .put,
        headers: [String: String] = [:],
        file: Data,
        fileName: String,
        mimeType: String
    ) async throws -> HTTPResponse {
        let boundary = UUID().uuidString
        var allHeaders = headers
        allHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let request = buildRequest(method: method, url: url, headers: allHeaders, body: body)

        logger.debug("[UPLOAD-\(method.rawValue)] \(url)")

        return try await withRetry {
            try await self.performRequest(request)
        }
    }

    // MARK: - Auto-Refresh Execution

    /// Executes an HTTP request with automatic token refresh on 401 errors.
    ///
    /// If the request fails with a 401 status code, this method will attempt to
    /// refresh the access token using the provided handler and retry the request
    /// with the new token.
    ///
    /// - Parameters:
    ///   - method: The HTTP method to use.
    ///   - url: The URL to request.
    ///   - headers: HTTP headers. The Authorization header will be updated with refreshed token.
    ///   - body: Optional request body data.
    ///   - refreshHandler: The handler responsible for refreshing the token.
    /// - Returns: An `HTTPResponse` containing the response data.
    /// - Throws: `InsForgeError` if the request fails after retry, or if token refresh fails.
    public func executeWithAutoRefresh(
        _ method: HTTPMethod,
        url: URL,
        headers: [String: String],
        body: Data? = nil,
        refreshHandler: TokenRefreshHandler
    ) async throws -> HTTPResponse {
        do {
            // First attempt with current headers
            return try await execute(method, url: url, headers: headers, body: body)
        } catch let error as InsForgeError {
            // Check if it's a 401 unauthorized error
            if case .httpError(let statusCode, _, _, _) = error, statusCode == 401 {
                logger.debug("Received 401, attempting token refresh...")

                // Try to refresh the token
                do {
                    let newToken = try await refreshHandler.refreshToken()
                    logger.debug("Token refreshed successfully, retrying request...")

                    // Update headers with new token and retry
                    var updatedHeaders = headers
                    updatedHeaders["Authorization"] = "Bearer \(newToken)"

                    return try await execute(method, url: url, headers: updatedHeaders, body: body)
                } catch {
                    logger.error("Token refresh failed: \(error)")
                    // Re-throw the original 401 error or auth required error
                    throw InsForgeError.authenticationRequired
                }
            }

            // Not a 401 error, re-throw original error
            throw error
        }
    }

    /// Uploads multipart form data with automatic token refresh on 401 errors.
    ///
    /// If the upload fails with a 401 status code, this method will attempt to
    /// refresh the access token using the provided handler and retry the upload
    /// with the new token.
    ///
    /// - Parameters:
    ///   - url: The URL to upload to.
    ///   - method: The HTTP method to use. Defaults to `.put`.
    ///   - headers: HTTP headers. The Authorization header will be updated with refreshed token.
    ///   - file: The file data to upload.
    ///   - fileName: The name of the file.
    ///   - mimeType: The MIME type of the file.
    ///   - refreshHandler: The handler responsible for refreshing the token.
    /// - Returns: An `HTTPResponse` containing the response data.
    /// - Throws: `InsForgeError` if the upload fails after retry, or if token refresh fails.
    public func uploadWithAutoRefresh(
        url: URL,
        method: HTTPMethod = .put,
        headers: [String: String],
        file: Data,
        fileName: String,
        mimeType: String,
        refreshHandler: TokenRefreshHandler
    ) async throws -> HTTPResponse {
        do {
            // First attempt with current headers
            return try await upload(url: url, method: method, headers: headers, file: file, fileName: fileName, mimeType: mimeType)
        } catch let error as InsForgeError {
            // Check if it's a 401 unauthorized error
            if case .httpError(let statusCode, _, _, _) = error, statusCode == 401 {
                logger.debug("Received 401 during upload, attempting token refresh...")

                // Try to refresh the token
                do {
                    let newToken = try await refreshHandler.refreshToken()
                    logger.debug("Token refreshed successfully, retrying upload...")

                    // Update headers with new token and retry
                    var updatedHeaders = headers
                    updatedHeaders["Authorization"] = "Bearer \(newToken)"

                    return try await upload(url: url, method: method, headers: updatedHeaders, file: file, fileName: fileName, mimeType: mimeType)
                } catch {
                    logger.error("Token refresh failed during upload: \(error)")
                    throw InsForgeError.authenticationRequired
                }
            }

            // Not a 401 error, re-throw original error
            throw error
        }
    }
}

/// HTTP Response wrapper.
///
/// Contains the response data and metadata from an HTTP request.
public struct HTTPResponse: Sendable {
    /// The raw response data.
    public let data: Data
    /// The underlying HTTP URL response.
    public let response: HTTPURLResponse

    /// The HTTP status code of the response.
    public var statusCode: Int {
        response.statusCode
    }

    /// Decodes the response data to the specified type.
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - decoder: An optional custom JSON decoder. Defaults to `nil`.
    /// - Returns: The decoded value.
    /// - Throws: A decoding error if the data cannot be decoded.
    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder? = nil) throws -> T {
        let jsonDecoder = decoder ?? {
            let defaultDecoder = JSONDecoder()
            defaultDecoder.dateDecodingStrategy = iso8601WithFractionalSecondsDecodingStrategy()
            return defaultDecoder
        }()

        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            // Log detailed decoding error
            let logger = InsForgeLoggerFactory.shared
            logger.error("Failed to decode \(T.self): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.debug("Response data: \(responseString)")
            }
            throw error
        }
    }
}

/// Standard error response from API.
///
/// Represents the error format returned by InsForge API endpoints.
public struct ErrorResponse: Codable, Sendable {
    /// The error code or type.
    public let error: String?
    /// A human-readable error message.
    public let message: String
    /// The HTTP status code.
    public let statusCode: Int?
    /// Suggested next actions to resolve the error.
    public let nextActions: String?
}
