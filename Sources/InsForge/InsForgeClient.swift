import Foundation
import InsForgeCore
import InsForgeAuth
import InsForgeDatabase
import InsForgeStorage
import InsForgeFunctions
import InsForgeAI
import InsForgeRealtime

/// Main InsForge client following the Supabase pattern
public final class InsForgeClient: Sendable {
    // MARK: - Properties

    /// Configuration options
    public let options: InsForgeClientOptions

    /// Base URL for the InsForge instance
    public let insForgeURL: URL

    /// API key for authentication
    public let apiKey: String

    /// Headers shared across all requests
    private let _headers: [String: String]
    public var headers: [String: String] { _headers }

    // MARK: - Sub-clients

    private let _auth: AuthClient
    public var auth: AuthClient { _auth }

    private let mutableState = LockIsolated(MutableState())

    private struct MutableState {
        var database: DatabaseClient?
        var storage: StorageClient?
        var functions: FunctionsClient?
        var ai: AIClient?
        var realtime: RealtimeClient?
    }

    // MARK: - Initialization

    /// Initialize InsForge client
    /// - Parameters:
    ///   - insForgeURL: Base URL for your InsForge instance
    ///   - apiKey: Anonymous or service role API key
    ///   - options: Configuration options
    public init(
        insForgeURL: URL,
        apiKey: String,
        options: InsForgeClientOptions = .init()
    ) {
        self.insForgeURL = insForgeURL
        self.apiKey = apiKey
        self.options = options

        // Build shared headers
        var headers = options.global.headers
        headers["apikey"] = apiKey
        headers["Authorization"] = "Bearer \(apiKey)"
        headers["X-Client-Info"] = "insforge-swift/\(InsForgeClient.version)"
        self._headers = headers

        // Initialize auth client
        self._auth = AuthClient(
            url: insForgeURL.appendingPathComponent("api/auth"),
            headers: headers,
            options: options.auth,
            logger: options.global.logger
        )
    }

    // MARK: - Database

    public var database: DatabaseClient {
        mutableState.withValue { state in
            if state.database == nil {
                state.database = DatabaseClient(
                    url: insForgeURL.appendingPathComponent("api/database"),
                    headers: headers,
                    options: options.database,
                    logger: options.global.logger
                )
            }
            return state.database!
        }
    }

    // MARK: - Storage

    public var storage: StorageClient {
        mutableState.withValue { state in
            if state.storage == nil {
                state.storage = StorageClient(
                    url: insForgeURL.appendingPathComponent("api/storage"),
                    headers: headers,
                    logger: options.global.logger
                )
            }
            return state.storage!
        }
    }

    // MARK: - Functions

    public var functions: FunctionsClient {
        mutableState.withValue { state in
            if state.functions == nil {
                state.functions = FunctionsClient(
                    url: insForgeURL.appendingPathComponent("functions"),
                    headers: headers,
                    logger: options.global.logger
                )
            }
            return state.functions!
        }
    }

    // MARK: - AI

    public var ai: AIClient {
        mutableState.withValue { state in
            if state.ai == nil {
                state.ai = AIClient(
                    url: insForgeURL.appendingPathComponent("api/ai"),
                    headers: headers,
                    logger: options.global.logger
                )
            }
            return state.ai!
        }
    }

    // MARK: - Realtime

    public var realtime: RealtimeClient {
        mutableState.withValue { state in
            if state.realtime == nil {
                // Convert HTTP(S) URL to WS(S) URL
                var wsURL = insForgeURL
                if wsURL.scheme == "https" {
                    wsURL = URL(string: wsURL.absoluteString.replacingOccurrences(of: "https://", with: "wss://"))!
                } else if wsURL.scheme == "http" {
                    wsURL = URL(string: wsURL.absoluteString.replacingOccurrences(of: "http://", with: "ws://"))!
                }

                state.realtime = RealtimeClient(
                    url: wsURL.appendingPathComponent("api/realtime"),
                    apiKey: apiKey,
                    headers: headers,
                    logger: options.global.logger
                )
            }
            return state.realtime!
        }
    }

    // MARK: - Version

    static let version = "1.0.0"
}
