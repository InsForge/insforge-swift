import Foundation
import InsForgeCore
import Logging
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

/// Auth flow type for OAuth
public enum AuthFlowType: String, Sendable {
    case implicit
    case pkce
}

/// Authentication client options
public struct AuthOptions: Sendable {
    public let autoRefreshToken: Bool
    public let storage: AuthStorage
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

/// Authentication client for InsForge
public actor AuthClient {
    private let url: URL
    private let authComponent: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let storage: AuthStorage
    private let autoRefreshToken: Bool
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

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
    }

    /// Set callback for auth state changes
    public func setAuthStateChangeListener(_ listener: @escaping @Sendable (Session?) async -> Void) {
        self.onAuthStateChange = listener
    }

    // MARK: - Sign Up

    /// Register a new user with email and password
    public func signUp(
        email: String,
        password: String,
        name: String? = nil
    ) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("users")

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
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("[Auth] Request body: email=\(email), name=\(name ?? "nil")")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let token = authResponse.accessToken {
            let session = Session(
                accessToken: token,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("[Auth] Sign up successful for: \(email)")
        return authResponse
    }

    // MARK: - Sign In

    /// Sign in with email and password
    public func signIn(
        email: String,
        password: String
    ) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("sessions")

        let body: [String: String] = [
            "email": email,
            "password": password
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log password)
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("[Auth] Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            let session = Session(
                accessToken: accessToken,
                user: authResponse.user
            )
            try await storage.saveSession(session)

            // Notify listener about auth state change
            await onAuthStateChange?(session)
        }

        logger.debug("[Auth] Sign in successful for: \(email)")
        return authResponse
    }

    // MARK: - Sign Out

    /// Sign out current user
    public func signOut() async throws {
        try await storage.deleteSession()
        logger.debug("[Auth] User signed out")

        // Notify listener about auth state change (nil = signed out)
        await onAuthStateChange?(nil)
    }

    // MARK: - Get Current User

    /// Get current authenticated user
    public func getCurrentUser() async throws -> User {
        let endpoint = url.appendingPathComponent("sessions/current")
        let requestHeaders = try await getAuthHeaders()

        // Log request
        logger.debug("[Auth] GET \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: requestHeaders
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        struct UserResponse: Codable {
            let user: User
        }

        let userResponse = try response.decode(UserResponse.self)
        logger.debug("[Auth] Got current user: \(userResponse.user.email)")
        return userResponse.user
    }

    // MARK: - Get Session

    /// Get current session from storage
    /// Also triggers auth state change listener to update shared headers
    public func getSession() async throws -> Session? {
        let session = try await storage.getSession()
        // Notify listener to update headers when session is retrieved
        // This ensures headers are correct when app restarts with cached session
        if session != nil {
            await onAuthStateChange?(session)
        }
        return session
    }

    // MARK: - OAuth / Default Page Sign In

    /// Sign in using InsForge's default web authentication page
    /// Opens the browser to authenticate with OAuth (Google, GitHub, etc.) or email+password
    /// - Parameter redirectTo: Callback URL where auth result will be sent
    public func signInWithDefaultView(redirectTo: String) async {
        let endpoint = authComponent.appendingPathComponent("sign-in")

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect", value: redirectTo)
        ]

        guard let authURL = components.url else {
            logger.error("[Auth] Failed to construct sign-in URL")
            return
        }

        logger.debug("[Auth] Opening sign-in page: \(authURL)")

        #if os(macOS)
        await NSWorkspace.shared.open(authURL)
        #elseif os(iOS) || os(tvOS)
        // for tvOS, https://appkey.region.insforge.app/auth/callback should not respond.
        // It is only used to capture the URL opened by the system.
        await UIApplication.shared.open(authURL)
        #endif
    }

    /// Process authentication callback and create session
    /// Works with both OAuth and email+password authentication via default page
    /// - Parameter callbackURL: The URL received from authentication callback
    /// - Returns: AuthResponse with user and session
    public func handleAuthCallback(_ callbackURL: URL) async throws -> AuthResponse {
        logger.debug("[Auth] Handling auth callback: \(callbackURL.absoluteString)")

        // Parse callback URL parameters
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("[Auth] Invalid callback URL")
            throw InsForgeError.invalidURL
        }

        // Extract parameters
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        guard let accessToken = params["access_token"],
              let userId = params["user_id"],
              let email = params["email"] else {
            logger.error("[Auth] Missing required parameters in callback URL")
            throw InsForgeError.invalidResponse
        }

        let name = params["name"]
        let csrfToken = params["csrf_token"]

        // Create user object from callback data
        let user = User(
            id: userId,
            email: email,
            name: name,
            emailVerified: true, // OAuth users are typically verified
            metadata: nil,
            identities: nil,
            providerType: nil, // Provider info not available from callback
            role: "authenticated",
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save session
        let session = Session(
            accessToken: accessToken,
            user: user
        )
        try await storage.saveSession(session)

        // Notify listener about auth state change
        await onAuthStateChange?(session)

        logger.debug("[Auth] Auth callback handled successfully for: \(email)")

        // Return auth response
        return AuthResponse(
            user: user,
            accessToken: accessToken,
            requireEmailVerification: false,
            redirectTo: nil
        )
    }


    // MARK: - Email Verification

    /// Send email verification code
    public func sendEmailVerification(email: String) async throws {
        let endpoint = url.appendingPathComponent("email/send-verification")

        let body = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("[Auth] Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")

        logger.debug("[Auth] Verification email sent to: \(email)")
    }

    /// Verify email with OTP code
    public func verifyEmail(email: String? = nil, otp: String) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("email/verify")

        var body: [String: String] = ["otp": otp]
        if let email = email {
            body["email"] = email
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request (don't log OTP)
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("[Auth] Request body: email=\(email ?? "nil")")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            try await storage.saveSession(Session(
                accessToken: accessToken,
                user: authResponse.user
            ))
        }

        logger.debug("[Auth] Email verified successfully")
        return authResponse
    }

    // MARK: - Profile

    /// Get user profile by ID (public endpoint)
    /// - Parameter userId: The user ID to get profile for
    /// - Returns: Profile containing user ID and profile data
    public func getProfile(userId: String) async throws -> Profile {
        let endpoint = url.appendingPathComponent("profiles/\(userId)")

        // Log request
        logger.debug("[Auth] GET \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        let profile = try response.decode(Profile.self)
        logger.debug("[Auth] Fetched profile for user: \(userId)")
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
        logger.debug("[Auth] PATCH \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("[Auth] Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .patch,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("[Auth] Response body: \(responseString)")
        }

        let updatedProfile = try response.decode(Profile.self)
        logger.debug("[Auth] Updated current user's profile")
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
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        logger.trace("[Auth] Request body: email=\(email)")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")

        logger.debug("[Auth] Password reset email sent to: \(email)")
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
        logger.debug("[Auth] POST \(endpoint.absoluteString)")
        logger.trace("[Auth] Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("[Auth] Response: \(statusCode)")

        logger.debug("[Auth] Password reset successful")
    }

    // MARK: - Private Helpers

    private func getAuthHeaders() async throws -> [String: String] {
        guard let session = try await storage.getSession() else {
            throw InsForgeError.authenticationRequired
        }

        return headers.merging(["Authorization": "Bearer \(session.accessToken)"]) { $1 }
    }
}
