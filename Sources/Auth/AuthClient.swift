import Foundation
import InsForgeCore
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
    private let logger: (any InsForgeLogger)?

    /// Callback invoked when auth state changes (sign in/up/out)
    private var onAuthStateChange: (@Sendable (Session?) async -> Void)?

    public init(
        url: URL,
        authComponent: URL,
        headers: [String: String],
        options: AuthOptions = AuthOptions(),
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.authComponent = authComponent
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.storage = options.storage
        self.autoRefreshToken = options.autoRefreshToken
        self.logger = logger
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

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

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

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

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

        return authResponse
    }

    // MARK: - Sign Out

    /// Sign out current user
    public func signOut() async throws {
        try await storage.deleteSession()
        logger?.log("User signed out")

        // Notify listener about auth state change (nil = signed out)
        await onAuthStateChange?(nil)
    }

    // MARK: - Get Current User

    /// Get current authenticated user
    public func getCurrentUser() async throws -> User {
        let endpoint = url.appendingPathComponent("sessions/current")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: await getAuthHeaders()
        )

        struct UserResponse: Codable {
            let user: User
        }

        let userResponse = try response.decode(UserResponse.self)
        return userResponse.user
    }

    // MARK: - Get Session

    /// Get current session from storage
    public func getSession() async throws -> Session? {
        try await storage.getSession()
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
            logger?.log("Failed to construct sign-in URL")
            return
        }

        logger?.log("Opening sign-in page: \(authURL)")

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
        // Parse callback URL parameters
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
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

        _ = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        logger?.log("Verification email sent to \(email)")
    }

    /// Verify email with OTP code
    public func verifyEmail(email: String? = nil, otp: String) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("email/verify")

        var body: [String: String] = ["otp": otp]
        if let email = email {
            body["email"] = email
        }

        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        let authResponse = try response.decode(AuthResponse.self)

        // Save session if token is provided
        if let accessToken = authResponse.accessToken {
            try await storage.saveSession(Session(
                accessToken: accessToken,
                user: authResponse.user
            ))
        }

        return authResponse
    }

    // MARK: - Profile

    /// Get user profile by ID (public endpoint)
    /// - Parameter userId: The user ID to get profile for
    /// - Returns: Profile containing user ID and profile data
    public func getProfile(userId: String) async throws -> Profile {
        let endpoint = url.appendingPathComponent("profiles/\(userId)")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        let profile = try response.decode(Profile.self)
        logger?.log("Fetched profile for user: \(userId)")
        return profile
    }

    /// Update current user's profile
    /// - Parameter profile: Dictionary containing profile fields to update (name, avatar_url, and any custom fields)
    /// - Returns: Updated Profile
    public func updateProfile(_ profile: [String: Any]) async throws -> Profile {
        let endpoint = url.appendingPathComponent("profiles/current")

        let body: [String: Any] = ["profile": profile]
        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .patch,
            url: endpoint,
            headers: try await getAuthHeaders().merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        let updatedProfile = try response.decode(Profile.self)
        logger?.log("Updated current user's profile")
        return updatedProfile
    }

    // MARK: - Password Reset

    /// Send password reset email
    public func sendPasswordReset(email: String) async throws {
        let endpoint = url.appendingPathComponent("email/send-reset-password")

        let body = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        logger?.log("Password reset email sent to \(email)")
    }

    /// Reset password with OTP token
    public func resetPassword(otp: String, newPassword: String) async throws {
        let endpoint = url.appendingPathComponent("email/reset-password")

        let body = [
            "otp": otp,
            "newPassword": newPassword
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        logger?.log("Password reset successful")
    }

    // MARK: - Private Helpers

    private func getAuthHeaders() async throws -> [String: String] {
        guard let session = try await storage.getSession() else {
            throw InsForgeError.authenticationRequired
        }

        return headers.merging(["Authorization": "Bearer \(session.accessToken)"]) { $1 }
    }
}
