import Foundation

/// Errors thrown by InsForge SDK
public enum InsForgeError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case httpError(statusCode: Int, message: String, error: String?, nextActions: String?)
    case decodingError(Error)
    case encodingError(Error)
    case missingConfiguration(String)
    case authenticationRequired
    case unauthorized
    case notFound(String)
    case conflict(String)
    case validationError(String)
    case unknown(String)

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
