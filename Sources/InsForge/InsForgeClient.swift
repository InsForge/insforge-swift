import Foundation
import InsForgeCore
import InsForgeAuth
import InsForgeDatabase
import InsForgeStorage
import InsForgeFunctions
import InsForgeAI
import InsForgeRealtime
import Logging

/// Main InsForge client following the Supabase pattern
public final class InsForgeClient: Sendable {
    /// The logger instance for this client
    private let logger: Logging.Logger
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

        // Configure logging system
        InsForgeLoggerFactory.reconfigure(
            level: options.global.logLevel,
            destination: options.global.logDestination,
            subsystem: options.global.logSubsystem
        )
        self.logger = InsForgeLoggerFactory.shared

        // Build shared headers - use user-provided Authorization if present, otherwise use anonKey
        var headers = options.global.headers
        if headers["Authorization"] == nil {
            headers["Authorization"] = "Bearer \(anonKey)"
        }
        headers["User-Agent"] = "insforge-swift/\(InsForgeClient.version)"
        self._headers = LockIsolated(headers)

        // Initialize auth client (auth always uses API key for auth endpoints)
        self._auth = AuthClient(
            url: baseURL.appendingPathComponent("api/auth"),
            authComponent: baseURL.appendingPathComponent("auth"),
            headers: headers,
            options: options.auth
        )

        // Capture logger for use in closure
        let log = self.logger

        // Set up auth state change listener to automatically update headers
        Task { [weak self] in
            guard let self = self else { return }
            await self._auth.setAuthStateChangeListener { [weak self] session in
                guard let self = self else { return }
                if let session = session {
                    // User signed in - update to user token
                    self._headers.withValue { headers in
                        headers["Authorization"] = "Bearer \(session.accessToken)"
                    }
                    log.debug("Auth headers updated with user token")
                } else {
                    // User signed out - reset to InsForge key
                    self._headers.withValue { headers in
                        headers["Authorization"] = "Bearer \(self.anonKey)"
                    }
                    log.debug("Auth headers reset to InsForge key")
                }
            }

            // Check for existing session in storage and update headers if found
            // This ensures headers are correct when app restarts with cached session
            if let existingSession = try? await self._auth.getSession() {
                self._headers.withValue { headers in
                    headers["Authorization"] = "Bearer \(existingSession.accessToken)"
                }
                log.debug("Auth headers restored from cached session")
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
                    options: options.database
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
                    headersProvider: _headers
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
                    headersProvider: _headers
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
                    headersProvider: _headers
                )
            }
            return state.ai!
        }
    }

    // MARK: - Realtime

    public var realtime: RealtimeClient {
        mutableState.withValue { state in
            if state.realtime == nil {
                // Socket.IO uses HTTP URL and handles WebSocket upgrade internally
                state.realtime = RealtimeClient(
                    url: baseURL,
                    apiKey: anonKey,
                    headersProvider: _headers
                )
            }
            return state.realtime!
        }
    }

    // MARK: - Version

    static let version = "0.0.1"
}
