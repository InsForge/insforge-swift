import Foundation
import InsForgeCore
#if canImport(Security)
import Security
#endif

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

#if canImport(Security)
/// Errors thrown by `KeychainAuthStorage`.
public enum KeychainAuthStorageError: Error, LocalizedError, Sendable {
    case unexpectedData
    case operationFailed(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned an unexpected value"
        case .operationFailed(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain operation failed: \(message) (\(status))"
            }
            return "Keychain operation failed with status \(status)"
        }
    }
}

/// Keychain-based auth storage for Apple platforms.
public actor KeychainAuthStorage: AuthStorage {
    private let sessionAccount = "insforge.auth.session"
    private let pkceAccount = "insforge.auth.pkce_verifier"
    private let service: String
    private let accessGroup: String?

    /// Initialize with an optional custom service name and access group.
    /// - Parameters:
    ///   - service: Keychain service name used to namespace stored credentials.
    ///   - accessGroup: Optional Keychain access group for app group sharing.
    public init(
        service: String = "com.insforge.auth",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func saveSession(_ session: Session) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try save(data, account: sessionAccount)
    }

    public func getSession() async throws -> Session? {
        guard let data = try loadData(account: sessionAccount) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = iso8601WithFractionalSecondsDecodingStrategy()
        return try decoder.decode(Session.self, from: data)
    }

    public func deleteSession() async throws {
        try delete(account: sessionAccount)
    }

    public func savePKCEVerifier(_ verifier: String) async throws {
        guard let data = verifier.data(using: .utf8) else {
            throw InsForgeError.encodingError(NSError(domain: "KeychainAuthStorage", code: -1))
        }
        try save(data, account: pkceAccount)
    }

    public func getPKCEVerifier() async throws -> String? {
        guard let data = try loadData(account: pkceAccount) else {
            return nil
        }
        guard let verifier = String(data: data, encoding: .utf8) else {
            throw KeychainAuthStorageError.unexpectedData
        }
        return verifier
    }

    public func deletePKCEVerifier() async throws {
        try delete(account: pkceAccount)
    }

    private func save(_ data: Data, account: String) throws {
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributesToUpdate = [kSecValueData as String: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributesToUpdate)
            guard updateStatus == errSecSuccess else {
                throw KeychainAuthStorageError.operationFailed(status: updateStatus)
            }
        default:
            throw KeychainAuthStorageError.operationFailed(status: addStatus)
        }
    }

    private func loadData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainAuthStorageError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAuthStorageError.operationFailed(status: status)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAuthStorageError.operationFailed(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
#endif

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
