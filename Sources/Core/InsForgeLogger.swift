import Foundation
import Logging

#if canImport(os)
import os
#endif

// MARK: - Log Destination

/// Log output destination for InsForge SDK.
public enum LogDestination: Sendable {
    /// Output to standard console (print)
    case console
    /// Output to Apple's unified logging system (os.Logger)
    /// Recommended for iOS/macOS apps - logs are viewable in Console.app
    /// Requires iOS 14+ / macOS 11+ and Apple platforms only
    case osLog
    /// Disable all logging
    case none
    /// Custom log handler factory
    case custom(@Sendable (String) -> Logging.LogHandler)
}

// MARK: - InsForge Logger Factory

/// Factory for creating configured loggers for InsForge SDK.
public enum InsForgeLoggerFactory {
    /// The shared logger instance used by all InsForge modules.
    /// Configure via `InsForgeClientOptions.GlobalOptions.logLevel` and `logDestination`.
    public private(set) static var shared: Logging.Logger = Logging.Logger(label: "com.insforge.sdk")

    /// Configure the shared logger with specified level and destination.
    /// - Parameters:
    ///   - level: The minimum log level to output
    ///   - destination: Where to output logs
    ///   - subsystem: The subsystem identifier (used for osLog destination)
    public static func configure(
        level: Logging.Logger.Level = .info,
        destination: LogDestination = .console,
        subsystem: String = "com.insforge.sdk"
    ) {
        switch destination {
        case .console:
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = level
                return handler
            }
        case .osLog:
            #if canImport(os)
            LoggingSystem.bootstrap { label in
                if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
                    var handler = OSLogHandler(subsystem: subsystem, category: label)
                    handler.logLevel = level
                    return handler
                } else {
                    // Fallback to console on older OS versions
                    var handler = StreamLogHandler.standardOutput(label: label)
                    handler.logLevel = level
                    return handler
                }
            }
            #else
            // Fallback to console on non-Apple platforms
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = level
                return handler
            }
            #endif
        case .none:
            LoggingSystem.bootstrap { _ in
                SwiftLogNoOpLogHandler()
            }
        case .custom(let factory):
            LoggingSystem.bootstrap { label in
                var handler = factory(label)
                handler.logLevel = level
                return handler
            }
        }

        shared = Logging.Logger(label: subsystem)
        shared.logLevel = level
    }

    /// Reconfigure the logger at runtime.
    /// Use this instead of `configure()` when the logging system has already been bootstrapped.
    /// - Parameters:
    ///   - level: The minimum log level to output
    ///   - destination: Where to output logs
    ///   - subsystem: The subsystem identifier (used for osLog destination)
    public static func reconfigure(
        level: Logging.Logger.Level,
        destination: LogDestination,
        subsystem: String = "com.insforge.sdk"
    ) {
        var logger: Logging.Logger
        switch destination {
        case .console:
            logger = Logging.Logger(label: subsystem) { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = level
                return handler
            }
        case .osLog:
            #if canImport(os)
            logger = Logging.Logger(label: subsystem) { label in
                if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
                    var handler = OSLogHandler(subsystem: subsystem, category: label)
                    handler.logLevel = level
                    return handler
                } else {
                    // Fallback to console on older OS versions
                    var handler = StreamLogHandler.standardOutput(label: label)
                    handler.logLevel = level
                    return handler
                }
            }
            #else
            // Fallback to console on non-Apple platforms
            logger = Logging.Logger(label: subsystem) { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = level
                return handler
            }
            #endif
        case .none:
            logger = Logging.Logger(label: subsystem) { _ in
                SwiftLogNoOpLogHandler()
            }
        case .custom(let factory):
            logger = Logging.Logger(label: subsystem) { label in
                var handler = factory(label)
                handler.logLevel = level
                return handler
            }
        }
        logger.logLevel = level
        shared = logger
    }
}

// MARK: - OSLogHandler

#if canImport(os)
/// A SwiftLog handler that outputs to Apple's unified logging system (os.Logger).
///
/// This handler maps SwiftLog levels to os.Logger types:
/// - trace, debug -> .debug
/// - info, notice -> .info
/// - warning -> .default
/// - error -> .error
/// - critical -> .fault
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
public struct OSLogHandler: Logging.LogHandler {
    private let osLogger: os.Logger
    public var logLevel: Logging.Logger.Level = .info
    public var metadata: Logging.Logger.Metadata = [:]

    /// Creates an OSLogHandler with the specified subsystem and category.
    /// - Parameters:
    ///   - subsystem: The subsystem identifier (e.g., "com.myapp")
    ///   - category: The category for this logger (e.g., "networking")
    public init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let mergedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let metadataString = mergedMetadata.isEmpty ? "" : " \(mergedMetadata)"

        let fullMessage = "\(message)\(metadataString)"

        switch level {
        case .trace, .debug:
            osLogger.debug("\(fullMessage, privacy: .public)")
        case .info, .notice:
            osLogger.info("\(fullMessage, privacy: .public)")
        case .warning:
            osLogger.warning("\(fullMessage, privacy: .public)")
        case .error:
            osLogger.error("\(fullMessage, privacy: .public)")
        case .critical:
            osLogger.fault("\(fullMessage, privacy: .public)")
        }
    }
}
#endif

// MARK: - NoOp Handler

/// A log handler that discards all log messages.
public struct SwiftLogNoOpLogHandler: Logging.LogHandler {
    public var logLevel: Logging.Logger.Level = .critical
    public var metadata: Logging.Logger.Metadata = [:]

    public init() {}

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { nil }
        // swiftlint:disable:next unused_setter_value
        set { }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Discard all messages
    }
}

// MARK: - Date Decoding Strategy

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
