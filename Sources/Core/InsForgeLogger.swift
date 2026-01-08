import Foundation

/// Logger protocol for InsForge SDK.
///
/// Implement this protocol to provide custom logging behavior for the SDK.
public protocol InsForgeLogger: Sendable {
    /// Logs an informational message.
    /// - Parameter message: The message to log.
    func log(_ message: String)

    /// Logs an error message.
    /// - Parameter message: The error message to log.
    func error(_ message: String)
}

/// Custom date decoding strategy for ISO8601 with fractional seconds support.
///
/// Also supports date-only format (YYYY-MM-DD) commonly returned by PostgreSQL date columns.
/// - Returns: A custom `JSONDecoder.DateDecodingStrategy`.
public func iso8601WithFractionalSecondsDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
    .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)

        // Try ISO8601 with fractional seconds first
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: dateString) {
            return date
        }

        // Try ISO8601 without fractional seconds
        let isoWithoutFractional = ISO8601DateFormatter()
        isoWithoutFractional.formatOptions = [.withInternetDateTime]
        if let date = isoWithoutFractional.date(from: dateString) {
            return date
        }

        // Try date-only format (YYYY-MM-DD) - common for PostgreSQL date columns
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode date string '\(dateString)'. "
                + "Expected ISO8601 format or date-only format (YYYY-MM-DD)."
        )
    }
}

/// Console logger implementation.
///
/// Prints log messages to the standard output with an `[InsForge]` prefix.
public struct ConsoleLogger: InsForgeLogger {
    /// Creates a new console logger.
    public init() {}

    /// Logs an informational message to the console.
    /// - Parameter message: The message to log.
    public func log(_ message: String) {
        print("[InsForge] \(message)")
    }

    /// Logs an error message to the console.
    /// - Parameter message: The error message to log.
    public func error(_ message: String) {
        print("[InsForge Error] \(message)")
    }
}

/// No-op logger that discards all messages.
///
/// Use this logger when you want to disable logging.
public struct NoOpLogger: InsForgeLogger {
    /// Creates a new no-op logger.
    public init() {}

    /// Discards the log message.
    /// - Parameter message: The message to discard.
    public func log(_ message: String) {}

    /// Discards the error message.
    /// - Parameter message: The error message to discard.
    public func error(_ message: String) {}
}
