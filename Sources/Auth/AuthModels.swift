import Foundation

// MARK: - User

/// User model
public struct User: Codable, Sendable, Identifiable {
    public let id: String
    public let email: String
    public let emailVerified: Bool
    public let metadata: [String: AnyCodable]?
    public let providers: [String]?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, emailVerified, metadata, providers, createdAt, updatedAt
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

// MARK: - Session

/// Authentication session
public struct Session: Codable, Sendable {
    public let accessToken: String
    public let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken, user
    }
}

// MARK: - AuthResponse

/// Authentication response
public struct AuthResponse: Codable, Sendable {
    public let user: User
    public let accessToken: String?
    public let requireEmailVerification: Bool?
    public let redirectTo: String?

    enum CodingKeys: String, CodingKey {
        case user, accessToken, requireEmailVerification, redirectTo
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
