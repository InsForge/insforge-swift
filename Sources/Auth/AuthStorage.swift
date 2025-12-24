import Foundation
import InsForgeCore

/// Protocol for storing authentication sessions
public protocol AuthStorage: Sendable {
    func saveSession(_ session: Session) async throws
    func getSession() async throws -> Session?
    func deleteSession() async throws
}

/// UserDefaults-based auth storage
public actor UserDefaultsAuthStorage: AuthStorage {
    private let key = "insforge.auth.session"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveSession(_ session: Session) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        userDefaults.set(data, forKey: key)
    }

    public func getSession() async throws -> Session? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = iso8601WithFractionalSecondsDecodingStrategy()
        return try decoder.decode(Session.self, from: data)
    }

    public func deleteSession() async throws {
        userDefaults.removeObject(forKey: key)
    }
}

/// In-memory auth storage (for testing)
public actor InMemoryAuthStorage: AuthStorage {
    private var session: Session?

    public init() {}

    public func saveSession(_ session: Session) async throws {
        self.session = session
    }

    public func getSession() async throws -> Session? {
        return session
    }

    public func deleteSession() async throws {
        session = nil
    }
}
