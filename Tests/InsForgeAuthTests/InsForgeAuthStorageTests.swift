import Foundation
import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

final class InsForgeAuthStorageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testAuthOptionsUsesUserDefaultsStorageByDefault() {
        let options = AuthOptions()
        XCTAssertTrue(options.storage is UserDefaultsAuthStorage)
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

    func testAuthClientCanUseExplicitKeychainStorage() async throws {
        let service = "InsForgeAuthTests.\(UUID().uuidString)"
        let storage = KeychainAuthStorage(service: service)
        try? await storage.deleteSession()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "keychain-signin@example.com",
                    accessToken: "keychain-signin-access",
                    refreshToken: "keychain-signin-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let response = try await client.signIn(
            email: "keychain-signin@example.com",
            password: "super-secret"
        )
        let persistedSession = try await storage.getSession()

        XCTAssertEqual(response.accessToken, "keychain-signin-access")
        XCTAssertEqual(persistedSession?.accessToken, "keychain-signin-access")

        try? await storage.deleteSession()
    }
    #endif
}
