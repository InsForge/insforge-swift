import Foundation

/// Logger protocol for InsForge SDK
public protocol InsForgeLogger: Sendable {
    func log(_ message: String)
    func error(_ message: String)
}

/// Custom date decoding strategy for ISO8601 with fractional seconds support
public func iso8601WithFractionalSecondsDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
    .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)

        // Try ISO8601 with fractional seconds first, then without
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode date string '\(dateString)'. Expected ISO8601 format (with or without fractional seconds)."
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
