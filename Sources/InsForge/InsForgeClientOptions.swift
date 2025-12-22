import Foundation
import InsForgeCore
import InsForgeAuth

/// Configuration options for InsForge client
public struct InsForgeClientOptions: Sendable {
    /// Database configuration options
    public struct DatabaseOptions: Sendable {
        /// Default JSON encoder
        public let encoder: JSONEncoder

        /// Default JSON decoder
        public let decoder: JSONDecoder

        public init(
            encoder: JSONEncoder = .init(),
            decoder: JSONDecoder = .init()
        ) {
            self.encoder = encoder
            self.decoder = decoder
        }
    }

    /// Authentication configuration options
    public struct AuthOptions: Sendable {
        /// Auto refresh access token
        public let autoRefreshToken: Bool

        /// Storage for authentication tokens
        public let storage: AuthStorage

        /// Flow type for OAuth
        public let flowType: AuthFlowType

        public init(
            autoRefreshToken: Bool = true,
            storage: AuthStorage = UserDefaultsAuthStorage(),
            flowType: AuthFlowType = .pkce
        ) {
            self.autoRefreshToken = autoRefreshToken
            self.storage = storage
            self.flowType = flowType
        }
    }

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

    public let database: DatabaseOptions
    public let auth: AuthOptions
    public let global: GlobalOptions

    // MARK: - Initialization

    public init(
        database: DatabaseOptions = .init(),
        auth: AuthOptions = .init(),
        global: GlobalOptions = .init()
    ) {
        self.database = database
        self.auth = auth
        self.global = global
    }
}

/// Auth flow type for OAuth
public enum AuthFlowType: String, Sendable {
    case implicit
    case pkce
}
