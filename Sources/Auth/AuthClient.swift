import Foundation
import InsForgeCore
import Logging
import CryptoKit
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

/// Authentication client options
public struct AuthOptions: Sendable {
    public let autoRefreshToken: Bool
    public let storage: AuthStorage
    public let clientType: ClientType

    public init(
        autoRefreshToken: Bool = true,
        storage: AuthStorage = UserDefaultsAuthStorage(),
        clientType: ClientType = .mobile
    ) {
        self.autoRefreshToken = autoRefreshToken
        self.storage = storage
        self.clientType = clientType
    }
}

// MARK: - PKCE Helper

/// PKCE (Proof Key for Code Exchange) helper for OAuth flows
public struct PKCEHelper: Sendable {
    public let codeVerifier: String
    public let codeChallenge: String

    /// Generate a new PKCE code verifier and challenge pair
    public static func generate() -> PKCEHelper {
        // Generate random code verifier (43-128 characters)
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        return PKCEHelper(codeVerifier: verifier, codeChallenge: challenge)
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Authentication client for InsForge
public actor AuthClient {
    private let url: URL
    private let authComponent: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let storage: AuthStorage
    private let autoRefreshToken: Bool
    private let clientType: ClientType
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// In-memory access token cache
    /// - For new backend (with refreshToken): short-lived, refreshed automatically
    /// - For legacy backend (no refreshToken): restored from persisted session on app launch
    private var currentAccessToken: String?

    /// Current PKCE helper for OAuth flow (temporary, cleared after use)
    private var pendingPKCE: PKCEHelper?

    /// Callback invoked when auth state changes (sign in/up/out)
    private var onAuthStateChange: (@Sendable (Session?) async -> Void)?

    public init(
        url: URL,
        authComponent: URL,
        headers: [String: String],
        options: AuthOptions = AuthOptions()
    ) {
        self.url = url
        self.authComponent = authComponent
        self.headers = headers
        self.httpClient = HTTPClient()
        self.storage = options.storage
        self.autoRefreshToken = options.autoRefreshToken
        self.clientType = options.clientType
    }

    /// Set callback for auth state changes
    public func setAuthStateChangeListener(_ listener: @escaping @Sendable (Session?) async -> Void) {
        self.onAuthStateChange = listener
    }

    /// Get current access token (from memory or storage)
    ///
    /// Token retrieval strategy:
    /// 1. Return in-memory token if available
    /// 2. Fall back to persisted session's accessToken
    ///
    /// Note: For automatic token refresh on 401 errors, use the TokenRefreshHandler
    /// which is automatically configured in InsForgeClient for all API clients.
    public func getAccessToken() async throws -> String? {
        if let token = currentAccessToken {
            return token
        }
        // Try to restore from stored session
        if let session = try await storage.getSession() {
            currentAccessToken = session.accessToken
            return session.accessToken
        }
        return nil
    }

    // MARK: - Sign Up

    /// Register a new user with email and password
    public func signUp(
        email: String,
        password: String,
        name: String? = nil
    ) async throws -> AuthResponse {
        var components = URLComponents(url: url.appendingPathComponent("users"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_type", value: clientType.rawValue)
        ]

        guard let endpoint = components.url else {
            throw InsForgeError.invalidURL
        }

        var body: [String: Any] = [
            "email": email,
            "password": password
        ]
        if let name = name {
            body["name"] = name
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log password)
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("Request body: email=\(email), name=\(name ?? "nil")")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            // Store access token in memory
            currentAccessToken = accessToken

            // Persist session with both tokens
            // - accessToken: always persisted (for legacy backend compatibility & app restart)
            // - refreshToken: persisted if available (new backend with token refresh support)
            let session = Session(
                accessToken: accessToken,
                refreshToken: authResponse.refreshToken,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("Sign up successful for: \(email)")
        return authResponse
    }

    // MARK: - Sign In

    /// Sign in with email and password
    public func signIn(
        email: String,
        password: String
    ) async throws -> AuthResponse {
        var components = URLComponents(url: url.appendingPathComponent("sessions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_type", value: clientType.rawValue)
        ]

        guard let endpoint = components.url else {
            throw InsForgeError.invalidURL
        }

        let body: [String: String] = [
            "email": email,
            "password": password
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log password)
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            // Store access token in memory
            currentAccessToken = accessToken

            // Persist session with both tokens
            // - accessToken: always persisted (for legacy backend compatibility & app restart)
            // - refreshToken: persisted if available (new backend with token refresh support)
            let session = Session(
                accessToken: accessToken,
                refreshToken: authResponse.refreshToken,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("Sign in successful for: \(email)")
        return authResponse
    }

    // MARK: - Sign Out

    /// Sign out current user
    public func signOut() async throws {
        // Clear in-memory token
        currentAccessToken = nil
        pendingPKCE = nil

        try await storage.deleteSession()
        logger.debug("User signed out")

        // Notify listener about auth state change (nil = signed out)
        await onAuthStateChange?(nil)
    }

    // MARK: - Get Current User

    /// Get current authenticated user
    public func getCurrentUser() async throws -> User {
        let endpoint = url.appendingPathComponent("sessions/current")
        let requestHeaders = try await getAuthHeaders()

        // Log request
        logger.debug("GET \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: requestHeaders
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        struct UserResponse: Codable {
            let user: User
        }

        let userResponse = try response.decode(UserResponse.self)
        logger.debug("Got current user: \(userResponse.user.email)")
        return userResponse.user
    }

    // MARK: - Get Session

    /// Get current session from storage
    /// Also triggers auth state change listener to update shared headers
    public func getSession() async throws -> Session? {
        let session = try await storage.getSession()
        // Notify listener to update headers when session is retrieved
        // This ensures headers are correct when app restarts with cached session
        if let session = session {
            // Restore access token to memory
            currentAccessToken = session.accessToken
            await onAuthStateChange?(session)
        }
        return session
    }

    // MARK: - OAuth / Default Page Sign In

    /// Sign in with a specific OAuth provider using PKCE flow
    /// Opens the browser to authenticate with the specified provider (Google, GitHub, etc.)
    /// - Parameters:
    ///   - provider: The OAuth provider to use
    ///   - redirectTo: Callback URL where auth result will be sent
    /// - Note: After user completes OAuth, call `handleAuthCallback` with the callback URL to exchange the code for tokens
    public func signInWithOAuthView(provider: OAuthProvider, redirectTo: String) async throws {
        // Generate PKCE code verifier and challenge
        let pkce = PKCEHelper.generate()
        pendingPKCE = pkce

        // Build endpoint: /api/auth/oauth/{provider}?redirect_uri=xxx&code_challenge=xxx
        let endpoint = url.appendingPathComponent("oauth/\(provider.rawValue)")

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectTo),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge)
        ]

        guard let requestURL = components.url else {
            logger.error("Failed to construct OAuth URL")
            throw InsForgeError.invalidURL
        }

        // Log request
        logger.debug("GET \(requestURL.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        // Call API to get authUrl
        let response = try await httpClient.execute(
            .get,
            url: requestURL,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        // Parse response to get authUrl
        struct OAuthURLResponse: Codable {
            let authUrl: String
        }

        let oauthResponse = try response.decode(OAuthURLResponse.self)

        guard let authURL = URL(string: oauthResponse.authUrl) else {
            logger.error("Invalid authUrl in response: \(oauthResponse.authUrl)")
            throw InsForgeError.invalidURL
        }

        logger.debug("Opening OAuth page for \(provider.rawValue): \(authURL)")

        // Open browser
        #if os(macOS)
        await NSWorkspace.shared.open(authURL)
        #elseif os(iOS) || os(tvOS)
        await UIApplication.shared.open(authURL)
        #endif
    }

    /// Sign in using InsForge's default web authentication page with PKCE flow
    /// Opens the browser to authenticate with OAuth (Google, GitHub, etc.) or email+password
    /// - Parameter redirectTo: Callback URL where auth result will be sent
    /// - Note: After user completes authentication, call `handleAuthCallback` with the callback URL to exchange the code for tokens
    public func signInWithDefaultView(redirectTo: String) async {
        // Generate PKCE code verifier and challenge
        let pkce = PKCEHelper.generate()
        pendingPKCE = pkce

        let endpoint = authComponent.appendingPathComponent("sign-in")

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect", value: redirectTo),
            URLQueryItem(name: "client_type", value: clientType.rawValue),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge)
        ]

        guard let authURL = components.url else {
            logger.error("Failed to construct sign-in URL")
            return
        }

        logger.debug("Opening sign-in page: \(authURL)")

        #if os(macOS)
        await NSWorkspace.shared.open(authURL)
        #elseif os(iOS) || os(tvOS)
        await UIApplication.shared.open(authURL)
        #endif
    }

    /// Process authentication callback and exchange code for tokens (PKCE flow)
    /// Works with both OAuth and email+password authentication via default page
    /// - Parameter callbackURL: The URL received from authentication callback containing insforge_code
    /// - Returns: AuthResponse with user and session
    public func handleAuthCallback(_ callbackURL: URL) async throws -> AuthResponse {
        logger.debug("Handling auth callback: \(callbackURL.absoluteString)")

        // Parse callback URL parameters
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("Invalid callback URL")
            throw InsForgeError.invalidURL
        }

        // Extract parameters
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        // Check for insforge_code (PKCE flow)
        if let code = params["insforge_code"] {
            return try await exchangeCodeForTokens(code: code)
        }

        // Legacy flow: direct token in callback (for backwards compatibility)
        guard let accessToken = params["access_token"],
              let userId = params["user_id"],
              let email = params["email"] else {
            logger.error("Missing required parameters in callback URL")
            throw InsForgeError.invalidResponse
        }

        let name = params["name"]
        let refreshToken = params["refresh_token"]

        // Create user object from callback data
        let user = User(
            id: userId,
            email: email,
            name: name,
            emailVerified: true,
            metadata: nil,
            identities: nil,
            providerType: nil,
            role: "authenticated",
            createdAt: Date(),
            updatedAt: Date()
        )

        // Store access token in memory
        currentAccessToken = accessToken

        // Persist session with both tokens
        // - accessToken: always persisted (for legacy backend compatibility & app restart)
        // - refreshToken: persisted if available (new backend with token refresh support)
        let session = Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user
        )
        try await storage.saveSession(session)

        // Notify listener about auth state change
        await onAuthStateChange?(session)

        logger.debug("Auth callback handled successfully for: \(email)")

        return AuthResponse(
            user: user,
            accessToken: accessToken,
            refreshToken: refreshToken,
            requireEmailVerification: false,
            redirectTo: nil
        )
    }

    /// Exchange authorization code for tokens (PKCE flow)
    /// - Parameter code: The authorization code received from OAuth callback
    /// - Returns: AuthResponse with user and tokens
    public func exchangeCodeForTokens(code: String) async throws -> AuthResponse {
        guard let pkce = pendingPKCE else {
            logger.error("No pending PKCE flow found")
            throw InsForgeError.invalidResponse
        }

        // Clear pending PKCE
        let codeVerifier = pkce.codeVerifier
        pendingPKCE = nil

        var components = URLComponents(url: url.appendingPathComponent("oauth/exchange"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_type", value: clientType.rawValue)
        ]

        guard let endpoint = components.url else {
            throw InsForgeError.invalidURL
        }

        let body: [String: String] = [
            "code": code,
            "code_verifier": codeVerifier
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            // Store access token in memory
            currentAccessToken = accessToken

            // Persist session with both tokens
            // - accessToken: always persisted (for legacy backend compatibility & app restart)
            // - refreshToken: persisted if available (new backend with token refresh support)
            let session = Session(
                accessToken: accessToken,
                refreshToken: authResponse.refreshToken,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("Code exchange successful for: \(authResponse.user.email)")
        return authResponse
    }


    // MARK: - Email Verification

    /// Send email verification code
    public func sendEmailVerification(email: String) async throws {
        let endpoint = url.appendingPathComponent("email/send-verification")

        let body = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")

        logger.debug("Verification email sent to: \(email)")
    }

    /// Verify email with OTP code
    public func verifyEmail(email: String? = nil, otp: String) async throws -> AuthResponse {
        var components = URLComponents(url: url.appendingPathComponent("email/verify"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_type", value: clientType.rawValue)
        ]

        guard let endpoint = components.url else {
            throw InsForgeError.invalidURL
        }

        var body: [String: String] = ["otp": otp]
        if let email = email {
            body["email"] = email
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log OTP)
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("Request body: email=\(email ?? "nil")")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            // Store access token in memory
            currentAccessToken = accessToken

            // Persist session with both tokens
            // - accessToken: always persisted (for legacy backend compatibility & app restart)
            // - refreshToken: persisted if available (new backend with token refresh support)
            let session = Session(
                accessToken: accessToken,
                refreshToken: authResponse.refreshToken,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("Email verified successfully")
        return authResponse
    }

    // MARK: - Profile

    /// Get user profile by ID (public endpoint)
    /// - Parameter userId: The user ID to get profile for
    /// - Returns: Profile containing user ID and profile data
    public func getProfile(userId: String) async throws -> Profile {
        let endpoint = url.appendingPathComponent("profiles/\(userId)")

        // Log request
        logger.debug("GET \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let profile = try response.decode(Profile.self)
        logger.debug("Fetched profile for user: \(userId)")
        return profile
    }

    /// Update current user's profile
    /// - Parameter profile: Dictionary containing profile fields to update (name, avatar_url, and any custom fields)
    /// - Returns: Updated Profile
    public func updateProfile(_ profile: [String: Any]) async throws -> Profile {
        let endpoint = url.appendingPathComponent("profiles/current")

        let body: [String: Any] = ["profile": profile]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = try await getAuthHeaders().merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("PATCH \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .patch,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let updatedProfile = try response.decode(Profile.self)
        logger.debug("Updated current user's profile")
        return updatedProfile
    }

    // MARK: - Password Reset

    /// Send password reset email
    public func sendPasswordReset(email: String) async throws {
        let endpoint = url.appendingPathComponent("email/send-reset-password")

        let body = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")

        logger.debug("Password reset email sent to: \(email)")
    }

    /// Reset password with OTP token
    public func resetPassword(otp: String, newPassword: String) async throws {
        let endpoint = url.appendingPathComponent("email/reset-password")

        let body = [
            "otp": otp,
            "newPassword": newPassword
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log OTP or password)
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")

        logger.debug("Password reset successful")
    }

    // MARK: - Token Refresh

    /// Refresh the access token using the stored refresh token
    /// - Returns: AuthResponse with new tokens
    /// - Throws: `InsForgeError.authenticationRequired` if no refresh token is available
    @discardableResult
    public func refreshAccessToken() async throws -> AuthResponse {
        guard let session = try await storage.getSession(),
              let refreshToken = session.refreshToken else {
            logger.error("No refresh token available")
            throw InsForgeError.authenticationRequired
        }

        var components = URLComponents(url: url.appendingPathComponent("refresh"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_type", value: clientType.rawValue)
        ]

        guard let endpoint = components.url else {
            throw InsForgeError.invalidURL
        }

        let body = ["refreshToken": refreshToken]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        // Check if refresh token is expired (401)
        if statusCode == 401 {
            // Clear session and require re-login
            currentAccessToken = nil
            try await storage.deleteSession()
            await onAuthStateChange?(nil)
            throw InsForgeError.authenticationRequired
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Update tokens
        if let newAccessToken = authResponse.accessToken {
            // Store new access token in memory
            currentAccessToken = newAccessToken

            // Persist session with updated tokens
            // - accessToken: always persisted (for legacy backend compatibility & app restart)
            // - refreshToken: use new one if provided, otherwise keep the old one
            let newSession = Session(
                accessToken: newAccessToken,
                refreshToken: authResponse.refreshToken ?? refreshToken,
                user: authResponse.user
            )
            try await storage.saveSession(newSession)

            // Notify listener about updated session
            await onAuthStateChange?(newSession)
        }

        logger.debug("Token refresh successful")
        return authResponse
    }

    // MARK: - Private Helpers

    private func getAuthHeaders() async throws -> [String: String] {
        // First try in-memory token
        if let token = currentAccessToken {
            return headers.merging(["Authorization": "Bearer \(token)"]) { $1 }
        }

        // Fall back to stored session
        guard let session = try await storage.getSession() else {
            throw InsForgeError.authenticationRequired
        }

        currentAccessToken = session.accessToken
        return headers.merging(["Authorization": "Bearer \(session.accessToken)"]) { $1 }
    }
}
