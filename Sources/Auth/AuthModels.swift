import Foundation

// MARK: - User

/// Identity provider information
public struct Identity: Codable, Sendable {
    public let provider: String
}

/// User model
public struct User: Codable, Sendable, Identifiable {
    public let id: String
    public let email: String
    public let name: String?
    public let emailVerified: Bool?
    public let metadata: [String: AnyCodable]?
    public let identities: [Identity]?
    public let providerType: String?
    public let role: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, name, emailVerified, metadata, identities, providerType, role, createdAt, updatedAt
    }

    // Computed property for backwards compatibility
    public var providers: [String]? {
        identities?.map { $0.provider }
    }

    // Convenience property for email verification status
    public var isEmailVerified: Bool {
        emailVerified ?? false
    }
}

// MARK: - Profile

/// User profile model
public struct Profile: Codable, Sendable {
    public let id: String
    public let profile: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, profile
    }
}

// MARK: - Client Type

/// Client type for authentication requests
public enum ClientType: String, Sendable {
    case web
    case mobile
    case desktop
}

// MARK: - Session

/// Authentication session
public struct Session: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, user
    }

    public init(accessToken: String, refreshToken: String? = nil, user: User) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

// MARK: - AuthResponse

/// Authentication response
public struct AuthResponse: Codable, Sendable {
    public let user: User
    public let accessToken: String?
    public let refreshToken: String?
    public let requireEmailVerification: Bool?
    public let redirectTo: String?
    public let csrfToken: String?

    enum CodingKeys: String, CodingKey {
        case user, accessToken, refreshToken, requireEmailVerification, redirectTo, csrfToken
    }

    public init(
        user: User,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        requireEmailVerification: Bool? = nil,
        redirectTo: String? = nil,
        csrfToken: String? = nil
    ) {
        self.user = user
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.requireEmailVerification = requireEmailVerification
        self.redirectTo = redirectTo
        self.csrfToken = csrfToken
    }
}

// MARK: - SignUpResponse

/// Sign up response - may require email verification before returning user/session
public struct SignUpResponse: Codable, Sendable {
    /// User object (nil when email verification is required)
    public let user: User?
    /// Access token (nil when email verification is required)
    public let accessToken: String?
    /// Refresh token (nil when email verification is required)
    public let refreshToken: String?
    /// Indicates if email verification is required before sign-in
    public let requireEmailVerification: Bool?

    enum CodingKeys: String, CodingKey {
        case user, accessToken, refreshToken, requireEmailVerification
    }

    /// Check if email verification is required
    public var needsEmailVerification: Bool {
        requireEmailVerification == true
    }

    /// Check if sign up completed with session (no verification required)
    public var hasSession: Bool {
        accessToken != nil && user != nil
    }

    public init(
        user: User? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        requireEmailVerification: Bool? = nil
    ) {
        self.user = user
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.requireEmailVerification = requireEmailVerification
    }
}

// MARK: - OAuth Provider

/// OAuth provider types
public enum OAuthProvider: String, Sendable, CaseIterable {
    case google
    case github
    case discord
    case linkedin
    case facebook
    case instagram
    case tiktok
    case apple
    case x
    case spotify
    case microsoft
}

// MARK: - AnyCodable

/// Type-erased Codable value
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
