import Foundation
import InsForgeCore

/// Authentication client for InsForge
public actor AuthClient {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let storage: AuthStorage
    private let autoRefreshToken: Bool
    private let logger: (any InsForgeLogger)?

    public init(
        url: URL,
        headers: [String: String],
        options: InsForgeClientOptions.AuthOptions,
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.storage = options.storage
        self.autoRefreshToken = options.autoRefreshToken
        self.logger = logger
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
            try await storage.saveSession(Session(
                accessToken: token,
                user: authResponse.user
            ))
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

        // Save session
        try await storage.saveSession(Session(
            accessToken: authResponse.accessToken,
            user: authResponse.user
        ))

        return authResponse
    }

    // MARK: - Sign Out

    /// Sign out current user
    public func signOut() async throws {
        try await storage.deleteSession()
        logger?.log("User signed out")
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

    // MARK: - OAuth

    /// Get OAuth URL for provider
    public func getOAuthURL(
        provider: OAuthProvider,
        redirectTo: String
    ) async throws -> URL {
        let endpoint = url
            .appendingPathComponent("oauth")
            .appendingPathComponent(provider.rawValue)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectTo)
        ]

        guard let url = components?.url else {
            throw InsForgeError.invalidURL
        }

        let response = try await httpClient.execute(
            .get,
            url: url,
            headers: headers
        )

        struct OAuthURLResponse: Codable {
            let authUrl: String
        }

        let oauthResponse = try response.decode(OAuthURLResponse.self)

        guard let authURL = URL(string: oauthResponse.authUrl) else {
            throw InsForgeError.invalidURL
        }

        return authURL
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

        // Save session
        try await storage.saveSession(Session(
            accessToken: authResponse.accessToken,
            user: authResponse.user
        ))

        return authResponse
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
