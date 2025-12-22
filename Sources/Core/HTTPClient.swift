import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP method types
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// HTTP Client for making network requests
public actor HTTPClient: Sendable {
    private let session: URLSession
    private let logger: (any InsForgeLogger)?

    public init(
        session: URLSession = .shared,
        logger: (any InsForgeLogger)? = nil
    ) {
        self.session = session
        self.logger = logger
    }

    /// Execute HTTP request
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

        logger?.log("[\(method.rawValue)] \(url)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger?.log("Request body: \(bodyString)")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InsForgeError.invalidResponse
            }

            logger?.log("Response status: \(httpResponse.statusCode)")

            let httpResponseObj = HTTPResponse(
                data: data,
                response: httpResponse
            )

            // Check for errors
            if !(200..<300).contains(httpResponse.statusCode) {
                let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
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
            logger?.log("Network error: \(error)")
            throw InsForgeError.networkError(error)
        }
    }

    /// Upload multipart form data
    public func upload(
        url: URL,
        headers: [String: String] = [:],
        file: Data,
        fileName: String,
        mimeType: String
    ) async throws -> HTTPResponse {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.put.rawValue

        // Set headers
        var allHeaders = headers
        allHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Create multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(file)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logger?.log("[UPLOAD] \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsForgeError.invalidResponse
        }

        logger?.log("Upload response status: \(httpResponse.statusCode)")

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
}

/// HTTP Response wrapper
public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public var statusCode: Int {
        response.statusCode
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .init()) throws -> T {
        try decoder.decode(type, from: data)
    }
}

/// Standard error response from API
public struct ErrorResponse: Codable, Sendable {
    public let error: String?
    public let message: String
    public let statusCode: Int?
    public let nextActions: String?
}
