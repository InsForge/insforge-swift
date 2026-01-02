import Foundation

/// Logger protocol for InsForge SDK
public protocol InsForgeLogger: Sendable {
    func log(_ message: String)
    func error(_ message: String)
}

/// Custom date decoding strategy for ISO8601 with fractional seconds support
/// Also supports date-only format (YYYY-MM-DD) commonly returned by PostgreSQL date columns
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
            debugDescription: "Cannot decode date string '\(dateString)'. Expected ISO8601 format or date-only format (YYYY-MM-DD)."
        )
    }
}

/// Console logger implementation
public struct ConsoleLogger: InsForgeLogger {
    public init() {}

    public func log(_ message: String) {
        print("[InsForge] \(message)")
    }

    public func error(_ message: String) {
        print("[InsForge Error] \(message)")
    }
}

/// No-op logger
public struct NoOpLogger: InsForgeLogger {
    public init() {}

    public func log(_ message: String) {}
    public func error(_ message: String) {}
}
