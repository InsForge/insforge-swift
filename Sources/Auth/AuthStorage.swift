import Foundation
import InsForgeCore

/// Protocol for storing authentication sessions
public protocol AuthStorage: Sendable {
    func saveSession(_ session: Session) async throws
    func getSession() async throws -> Session?
    func deleteSession() async throws

    // PKCE storage for OAuth flow (survives app restart during OAuth)
    func savePKCEVerifier(_ verifier: String) async throws
    func getPKCEVerifier() async throws -> String?
    func deletePKCEVerifier() async throws
}

/// UserDefaults-based auth storage
public actor UserDefaultsAuthStorage: AuthStorage {
    private let sessionKey = "insforge.auth.session"
    private let pkceKey = "insforge.auth.pkce_verifier"
    private let userDefaults: UserDefaults

    /// Initialize with optional UserDefaults
    /// - Parameter userDefaults: Custom UserDefaults instance. If nil, uses a suite-based UserDefaults
    ///   that works reliably for Swift Package executables (where Bundle.main.bundleIdentifier may be nil)
    public init(userDefaults: UserDefaults? = nil) {
        // Use suite-based UserDefaults for reliability in Swift Package executables
        // This ensures PKCE verifier survives across process restarts during OAuth flow
        if let userDefaults = userDefaults {
            self.userDefaults = userDefaults
        } else {
            // Use a fixed suite name that works regardless of bundle identifier
            self.userDefaults = UserDefaults(suiteName: "com.insforge.auth") ?? .standard
        }
    }

    public func saveSession(_ session: Session) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        userDefaults.set(data, forKey: sessionKey)
    }

    public func getSession() async throws -> Session? {
        guard let data = userDefaults.data(forKey: sessionKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = iso8601WithFractionalSecondsDecodingStrategy()
        return try decoder.decode(Session.self, from: data)
    }

    public func deleteSession() async throws {
        userDefaults.removeObject(forKey: sessionKey)
    }

    // MARK: - PKCE Storage

    public func savePKCEVerifier(_ verifier: String) async throws {
        userDefaults.set(verifier, forKey: pkceKey)
        userDefaults.synchronize()  // Force immediate write to disk
    }

    public func getPKCEVerifier() async throws -> String? {
        return userDefaults.string(forKey: pkceKey)
    }

    public func deletePKCEVerifier() async throws {
        userDefaults.removeObject(forKey: pkceKey)
    }
}

/// In-memory auth storage (for testing)
public actor InMemoryAuthStorage: AuthStorage {
    private var session: Session?
    private var pkceVerifier: String?

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

    // MARK: - PKCE Storage

    public func savePKCEVerifier(_ verifier: String) async throws {
        self.pkceVerifier = verifier
    }

    public func getPKCEVerifier() async throws -> String? {
        return pkceVerifier
    }

    public func deletePKCEVerifier() async throws {
        pkceVerifier = nil
    }
}
