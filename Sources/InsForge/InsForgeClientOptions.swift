import Foundation
import InsForgeCore
import InsForgeAuth
import InsForgeDatabase

/// Configuration options for InsForge client
public struct InsForgeClientOptions: Sendable {
    /// Global configuration options
    public struct GlobalOptions: Sendable {
        /// Additional headers to include in all requests
        public let headers: [String: String]

        /// URL session for network requests
        public let session: URLSession

        /// Logger instance
        public let logger: (any InsForgeLogger)?

        public init(
            headers: [String: String] = [:],
            session: URLSession = .shared,
            logger: (any InsForgeLogger)? = nil
        ) {
            self.headers = headers
            self.session = session
            self.logger = logger
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
