import Foundation
import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

final class InsForgeAuthStorageMigrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    #if canImport(Security) && (os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS))
    func testKeychainAuthStoragePersistsSessionAndPKCEVerifier() async throws {
        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let storage = KeychainAuthStorage(service: service)
        try? await storage.deleteSession()
        try? await storage.deletePKCEVerifier()

        let session = AuthTestSupport.makeSession(
            accessToken: "keychain-access",
            refreshToken: "keychain-refresh",
            email: "keychain@example.com"
        )

        try await storage.saveSession(session)
        try await storage.savePKCEVerifier("pkce-verifier")

        let restoredSession = try await storage.getSession()
        let restoredVerifier = try await storage.getPKCEVerifier()

        XCTAssertEqual(restoredSession?.accessToken, "keychain-access")
        XCTAssertEqual(restoredSession?.refreshToken, "keychain-refresh")
        XCTAssertEqual(restoredSession?.user.email, "keychain@example.com")
        XCTAssertEqual(restoredVerifier, "pkce-verifier")

        try await storage.deleteSession()
        try await storage.deletePKCEVerifier()

        let deletedSession = try await storage.getSession()
        let deletedVerifier = try await storage.getPKCEVerifier()

        XCTAssertNil(deletedSession)
        XCTAssertNil(deletedVerifier)
    }

    func testAuthOptionsUsesMigrationAwareStorageByDefaultOnApplePlatforms() {
        let options = AuthOptions()
        XCTAssertTrue(options.storage is MigratingAuthStorage)
    }

    func testMigratingAuthStorageRestoresLegacySessionAndMovesItToPrimary() async throws {
        let suiteName = "InsForgeAuthTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let primary = KeychainAuthStorage(service: service)
        let legacy = UserDefaultsAuthStorage(userDefaults: userDefaults)
        let storage = MigratingAuthStorage(primary: primary, legacy: legacy)

        try? await primary.deleteSession()
        try await legacy.deleteSession()

        let session = AuthTestSupport.makeSession(
            accessToken: "legacy-access",
            refreshToken: "legacy-refresh",
            email: "legacy-session@example.com"
        )
        try await legacy.saveSession(session)

        let restoredSession = try await storage.getSession()
        let remainingLegacySession = try await legacy.getSession()
        let migratedPrimarySession = try await primary.getSession()

        XCTAssertEqual(restoredSession?.accessToken, "legacy-access")
        XCTAssertEqual(restoredSession?.refreshToken, "legacy-refresh")
        XCTAssertEqual(restoredSession?.user.email, "legacy-session@example.com")
        XCTAssertNil(remainingLegacySession)
        XCTAssertEqual(migratedPrimarySession?.accessToken, "legacy-access")

        try? await primary.deleteSession()
    }

    func testGetAccessTokenRestoresLegacyDefaultSessionThroughMigratingStorage() async throws {
        let suiteName = "InsForgeAuthTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let primary = KeychainAuthStorage(service: service)
        let legacy = UserDefaultsAuthStorage(userDefaults: userDefaults)
        let storage = MigratingAuthStorage(primary: primary, legacy: legacy)

        try? await primary.deleteSession()
        try await legacy.deleteSession()

        let session = AuthTestSupport.makeSession(
            accessToken: "legacy-default-access",
            refreshToken: "legacy-default-refresh",
            email: "legacy-default@example.com"
        )
        try await legacy.saveSession(session)

        let client = AuthTestSupport.makeClient(storage: storage)

        let restoredToken = try await client.getAccessToken()
        let remainingLegacySession = try await legacy.getSession()
        let migratedPrimarySession = try await primary.getSession()

        XCTAssertEqual(restoredToken, "legacy-default-access")
        XCTAssertNil(remainingLegacySession)
        XCTAssertEqual(migratedPrimarySession?.accessToken, "legacy-default-access")

        try? await primary.deleteSession()
    }

    func testMigratingAuthStorageRestoresLegacyPKCEVerifierAndMovesItToPrimary() async throws {
        let suiteName = "InsForgeAuthTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let primary = KeychainAuthStorage(service: service)
        let legacy = UserDefaultsAuthStorage(userDefaults: userDefaults)
        let storage = MigratingAuthStorage(primary: primary, legacy: legacy)

        try? await primary.deletePKCEVerifier()
        try await legacy.deletePKCEVerifier()
        try await legacy.savePKCEVerifier("legacy-verifier")

        let restoredVerifier = try await storage.getPKCEVerifier()
        let remainingLegacyVerifier = try await legacy.getPKCEVerifier()
        let migratedPrimaryVerifier = try await primary.getPKCEVerifier()

        XCTAssertEqual(restoredVerifier, "legacy-verifier")
        XCTAssertNil(remainingLegacyVerifier)
        XCTAssertEqual(migratedPrimaryVerifier, "legacy-verifier")

        try? await primary.deletePKCEVerifier()
    }

    func testHandleAuthCallbackUsesLegacyDefaultPKCEVerifierThroughMigratingStorage() async throws {
        let suiteName = "InsForgeAuthTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let primary = KeychainAuthStorage(service: service)
        let legacy = UserDefaultsAuthStorage(userDefaults: userDefaults)
        let storage = MigratingAuthStorage(primary: primary, legacy: legacy)

        try? await primary.deletePKCEVerifier()
        try await legacy.deletePKCEVerifier()
        try await legacy.savePKCEVerifier("legacy-default-verifier")

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/oauth/exchange"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["code"] as? String, "oauth-code")
            XCTAssertEqual(body["code_verifier"] as? String, "legacy-default-verifier")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "accessToken": "migrated-access-token",
                    "refreshToken": "migrated-refresh-token",
                    "user": AuthTestSupport.makeUserJSON(email: "migrated-pkce@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let callbackURL = URL(string: "myapp://auth/callback?insforge_code=oauth-code")!

        let response = try await client.handleAuthCallback(callbackURL)
        let remainingLegacyVerifier = try await legacy.getPKCEVerifier()
        let remainingPrimaryVerifier = try await primary.getPKCEVerifier()
        let migratedPrimarySession = try await primary.getSession()

        XCTAssertEqual(response.accessToken, "migrated-access-token")
        XCTAssertNil(remainingLegacyVerifier)
        XCTAssertNil(remainingPrimaryVerifier)
        XCTAssertEqual(migratedPrimarySession?.accessToken, "migrated-access-token")

        try? await primary.deleteSession()
    }
    #else
    func testAuthOptionsUsesUserDefaultsStorageByDefaultOnUnsupportedPlatforms() {
        let options = AuthOptions()
        XCTAssertTrue(options.storage is UserDefaultsAuthStorage)
    }
    #endif
}
