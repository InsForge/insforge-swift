import Foundation

/// Categorized network-layer errors.
///
/// Provides meaningful Swift cases for common `NSError` codes that occur
/// at the transport layer, before any HTTP response is received.
public enum NetworkError: Error, LocalizedError, Sendable {
    /// The request timed out.
    case timeout
    /// No network connection is available.
    case noNetwork
    /// The request was cancelled by the caller.
    case cancelled
    /// The server's SSL/TLS certificate is invalid or untrusted.
    case sslError(String)
    /// A DNS lookup or host connection failed.
    case cannotConnect(String)
    /// Any other transport-layer error not matched above.
    case other(String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "The request timed out"
        case .noNetwork:
            return "No network connection available"
        case .cancelled:
            return "The request was cancelled"
        case .sslError(let message):
            return "SSL error: \(message)"
        case .cannotConnect(let message):
            return "Cannot connect to server: \(message)"
        case .other(let message):
            return "Network error: \(message)"
        }
    }

    /// Maps a raw `Error` (typically an `NSError`) to a `NetworkError` case.
    public static func from(_ error: Error) -> NetworkError {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed:
            return .noNetwork
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .sslError(error.localizedDescription)
        case NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed:
            return .cannotConnect(error.localizedDescription)
        default:
            return .other(error.localizedDescription)
        }
    }
}

/// Errors thrown by InsForge SDK.
///
/// This enum represents all possible errors that can occur when using the InsForge SDK,
/// including network errors, authentication failures, and validation issues.
public enum InsForgeError: Error, LocalizedError, Sendable {
    /// The provided URL is invalid or malformed.
    case invalidURL
    /// The server returned an invalid or unexpected response.
    case invalidResponse
    /// A categorized network-layer error occurred before any HTTP response was received.
    case networkError(NetworkError)
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
        case .networkError(let networkError):
            return networkError.errorDescription
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
