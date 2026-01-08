import Foundation
import InsForgeCore
import InsForgeAuth
import InsForgeDatabase
import Logging

/// Configuration options for InsForge client
public struct InsForgeClientOptions: Sendable {
    /// Global configuration options
    public struct GlobalOptions: Sendable {
        /// Additional headers to include in all requests
        public let headers: [String: String]

        /// URL session for network requests
        public let session: URLSession

        /// Log level for SDK output
        /// - trace: Most verbose, includes all internal details
        /// - debug: Detailed information for debugging
        /// - info: General operational information (default)
        /// - warning: Warnings that don't prevent operation
        /// - error: Errors that affect functionality
        /// - critical: Critical failures
        public let logLevel: Logging.Logger.Level

        /// Log output destination
        /// - console: Standard output (print)
        /// - osLog: Apple's unified logging system (recommended for iOS/macOS)
        /// - none: Disable logging
        /// - custom: Provide your own LogHandler factory
        public let logDestination: LogDestination

        /// Subsystem identifier for logging (used with osLog destination)
        public let logSubsystem: String

        /// Creates global options with logging configuration
        /// - Parameters:
        ///   - headers: Additional headers to include in all requests
        ///   - session: URL session for network requests
        ///   - logLevel: Minimum log level to output (default: .info)
        ///   - logDestination: Where to output logs (default: .console)
        ///   - logSubsystem: Subsystem identifier for logging (default: "com.insforge.sdk")
        public init(
            headers: [String: String] = [:],
            session: URLSession = .shared,
            logLevel: Logging.Logger.Level = .info,
            logDestination: LogDestination = .console,
            logSubsystem: String = "com.insforge.sdk"
        ) {
            self.headers = headers
            self.session = session
            self.logLevel = logLevel
            self.logDestination = logDestination
            self.logSubsystem = logSubsystem
        }
    }

    // MARK: - Properties

    public let database: InsForgeDatabase.DatabaseOptions
    public let auth: InsForgeAuth.AuthOptions
    public let global: GlobalOptions

    // MARK: - Initialization

    public init(
        database: InsForgeDatabase.DatabaseOptions = .init(),
        auth: InsForgeAuth.AuthOptions = .init(),
        global: GlobalOptions = .init()
    ) {
        self.database = database
        self.auth = auth
        self.global = global
    }
}
