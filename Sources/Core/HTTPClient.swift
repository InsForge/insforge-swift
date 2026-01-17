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

/// HTTP Client for making network requests.
///
/// This actor provides thread-safe HTTP request execution with support for
/// various HTTP methods, file uploads, and response decoding.
public actor HTTPClient {
    private let session: URLSession
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Creates a new HTTP client.
    /// - Parameter session: The URL session to use for requests. Defaults to `.shared`.
    public init(session: URLSession = .shared) {
        self.session = session
    }

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
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        // Set headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        logger.debug("[\(method.rawValue)] \(url)")
        if !headers.isEmpty {
            logger.trace("Request headers: \(headers)")
        }
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InsForgeError.invalidResponse
            }

            logger.debug("Response status: \(httpResponse.statusCode)")

            // Log response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.trace("Response body: \(responseString)")
            }

            let httpResponseObj = HTTPResponse(
                data: data,
                response: httpResponse
            )

            // Check for errors
            if !(200..<300).contains(httpResponse.statusCode) {
                let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                logger.error("HTTP Error: status=\(httpResponse.statusCode), message=\(error?.message ?? "Request failed")")
                throw InsForgeError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: error?.message ?? "Request failed",
                    error: error?.error,
                    nextActions: error?.nextActions
                )
            }

            return httpResponseObj
        } catch let error as InsForgeError {
            throw error
        } catch {
            logger.error("Network error: \(error)")
            throw InsForgeError.networkError(error)
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
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Set headers
        var allHeaders = headers
        allHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Create multipart body
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        request.httpBody = body

        logger.debug("[UPLOAD-\(method.rawValue)] \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsForgeError.invalidResponse
        }

        logger.debug("Upload response status: \(httpResponse.statusCode)")

        let httpResponseObj = HTTPResponse(
            data: data,
            response: httpResponse
        )

        if !(200..<300).contains(httpResponse.statusCode) {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw InsForgeError.httpError(
                statusCode: httpResponse.statusCode,
                message: error?.message ?? "Upload failed",
                error: error?.error,
                nextActions: error?.nextActions
            )
        }

        return httpResponseObj
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
