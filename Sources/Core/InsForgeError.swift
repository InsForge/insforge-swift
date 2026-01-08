import Foundation

/// Errors thrown by InsForge SDK.
///
/// This enum represents all possible errors that can occur when using the InsForge SDK,
/// including network errors, authentication failures, and validation issues.
public enum InsForgeError: Error, LocalizedError, Sendable {
    /// The provided URL is invalid or malformed.
    case invalidURL
    /// The server returned an invalid or unexpected response.
    case invalidResponse
    /// A network error occurred during the request.
    case networkError(Error)
    /// An HTTP error was returned by the server.
    case httpError(statusCode: Int, message: String, error: String?, nextActions: String?)
    /// Failed to decode the response data.
    case decodingError(Error)
    /// Failed to encode the request data.
    case encodingError(Error)
    /// A required configuration value is missing.
    case missingConfiguration(String)
    /// Authentication is required to perform this operation.
    case authenticationRequired
    /// The user is not authorized to perform this operation.
    case unauthorized
    /// The requested resource was not found.
    case notFound(String)
    /// A conflict occurred with the current state of the resource.
    case conflict(String)
    /// The request failed validation.
    case validationError(String)
    /// An unknown error occurred.
    case unknown(String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message, let error, _):
            if let error = error {
                return "HTTP \(statusCode): \(error) - \(message)"
            }
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .missingConfiguration(let key):
            return "Missing configuration: \(key)"
        case .authenticationRequired:
            return "Authentication required"
        case .unauthorized:
            return "Unauthorized: Invalid credentials or token"
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .conflict(let message):
            return "Conflict: \(message)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
