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
    public let baseURL: URL

    /// InsForge anon/public key for authentication
    public let anonKey: String

    /// Headers shared across all requests (thread-safe, dynamically updated)
    private let _headers: LockIsolated<[String: String]>


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
    ///   - baseURL: Base URL for your InsForge instance
    ///   - anonKey: Anonymous/public key (not service role key)
    ///   - options: Configuration options
    public init(
        baseURL: URL,
        anonKey: String,
        options: InsForgeClientOptions = .init()
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.options = options

        // Build shared headers with InsForge key as default Authorization
        var headers = options.global.headers
        headers["Authorization"] = "Bearer \(anonKey)"
        headers["User-Agent"] = "insforge-swift/\(InsForgeClient.version)"
        self._headers = LockIsolated(headers)

        // Initialize auth client (auth always uses API key for auth endpoints)
        self._auth = AuthClient(
            url: baseURL.appendingPathComponent("api/auth"),
            authComponent: baseURL.appendingPathComponent("auth"),
            headers: headers,
            options: options.auth,
            logger: options.global.logger
        )

        // Set up auth state change listener to automatically update headers
        Task {
            await _auth.setAuthStateChangeListener { [weak self] session in
                guard let self = self else { return }
                if let session = session {
                    // User signed in - update to user token
                    self._headers.withValue { headers in
                        headers["Authorization"] = "Bearer \(session.accessToken)"
                    }
                    options.global.logger?.log("Auth headers updated with user token")
                } else {
                    // User signed out - reset to InsForge key
                    self._headers.withValue { headers in
                        headers["Authorization"] = "Bearer \(self.anonKey)"
                    }
                    options.global.logger?.log("Auth headers reset to InsForge key")
                }
            }

            // Check for existing session in storage and update headers if found
            // This ensures headers are correct when app restarts with cached session
            if let existingSession = try? await _auth.getSession() {
                self._headers.withValue { headers in
                    headers["Authorization"] = "Bearer \(existingSession.accessToken)"
                }
                options.global.logger?.log("Auth headers restored from cached session")
            }
        }
    }

    // MARK: - Database

    public var database: DatabaseClient {
        mutableState.withValue { state in
            if state.database == nil {
                state.database = DatabaseClient(
                    url: baseURL.appendingPathComponent("api/database"),
                    headersProvider: _headers,
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
                    url: baseURL.appendingPathComponent("api/storage"),
                    headersProvider: _headers,
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
                    url: baseURL.appendingPathComponent("functions"),
                    headersProvider: _headers,
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
                    url: baseURL.appendingPathComponent("api/ai"),
                    headersProvider: _headers,
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
                var wsURL = baseURL
                if wsURL.scheme == "https" {
                    wsURL = URL(string: wsURL.absoluteString.replacingOccurrences(of: "https://", with: "wss://"))!
                } else if wsURL.scheme == "http" {
                    wsURL = URL(string: wsURL.absoluteString.replacingOccurrences(of: "http://", with: "ws://"))!
                }

                state.realtime = RealtimeClient(
                    url: wsURL.appendingPathComponent("api/realtime"),
                    apiKey: anonKey,
                    headersProvider: _headers,
                    logger: options.global.logger
                )
            }
            return state.realtime!
        }
    }

    // MARK: - Version

    static let version = "1.0.0"
}
