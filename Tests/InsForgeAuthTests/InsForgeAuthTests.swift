import Foundation
import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

final class InsForgeAuthTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testUserDecodingFromJSON() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "email": "test@example.com",
            "emailVerified": true,
            "identities": [{ "provider": "email" }],
            "createdAt": "2025-01-01T00:00:00Z",
            "updatedAt": "2025-01-01T00:00:00Z"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.emailVerified, true)
        XCTAssertEqual(user.providers, ["email"])
    }

    func testOAuthProviderCases() {
        let providers = OAuthProvider.allCases

        XCTAssertTrue(providers.contains(.google))
        XCTAssertTrue(providers.contains(.github))
        XCTAssertTrue(providers.contains(.apple))
        XCTAssertEqual(providers.count, 11)
    }

    func testGetAccessTokenRestoresPersistedSessionAndCachesItInMemory() async throws {
        let suiteName = "InsForgeAuthTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = UserDefaultsAuthStorage(userDefaults: userDefaults)
        let session = AuthTestSupport.makeSession(
            accessToken: "persisted-access",
            refreshToken: "persisted-refresh",
            email: "persisted@example.com"
        )
        try await storage.saveSession(session)

        let client = AuthTestSupport.makeClient(storage: storage)

        let restoredToken = try await client.getAccessToken()
        XCTAssertEqual(restoredToken, "persisted-access")

        try await storage.deleteSession()

        let cachedToken = try await client.getAccessToken()
        XCTAssertEqual(cachedToken, "persisted-access")
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

    func testAuthOptionsUsesKeychainStorageByDefaultOnApplePlatforms() {
        let options = AuthOptions()
        XCTAssertTrue(options.storage is KeychainAuthStorage)
    }
    #else
    func testAuthOptionsUsesUserDefaultsStorageByDefaultOnUnsupportedPlatforms() {
        let options = AuthOptions()
        XCTAssertTrue(options.storage is UserDefaultsAuthStorage)
    }
    #endif

    func testSignUpWithoutSessionWhenEmailVerificationIsRequired() async throws {
        let storage = InMemoryAuthStorage()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/users"
        } response: { request in
            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(queryItems?.first(where: { $0.name == "client_type" })?.value, "mobile")

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["email"] as? String, "signup@example.com")
            XCTAssertEqual(body["password"] as? String, "super-secret")
            XCTAssertEqual(body["name"] as? String, "New User")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: ["requireEmailVerification": true]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let response = try await client.signUp(
            email: "signup@example.com",
            password: "super-secret",
            name: "New User"
        )

        XCTAssertTrue(response.needsEmailVerification)
        XCTAssertFalse(response.hasSession)

        let storedSession = try await storage.getSession()
        let currentToken = try await client.getAccessToken()
        XCTAssertNil(storedSession)
        XCTAssertNil(currentToken)
    }

    func testSignUpWithImmediateSessionPersistsSessionAndNotifiesListener() async throws {
        let storage = InMemoryAuthStorage()
        let recorder = AuthStateRecorder()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/users"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "signup-success@example.com",
                    accessToken: "signup-access",
                    refreshToken: "signup-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        await client.setAuthStateChangeListener { session in
            await recorder.record(session)
        }

        let response = try await client.signUp(
            email: "signup-success@example.com",
            password: "super-secret",
            name: "Signed Up"
        )

        XCTAssertEqual(response.accessToken, "signup-access")

        let persistedSession = try await storage.getSession()
        XCTAssertEqual(persistedSession?.refreshToken, "signup-refresh")

        let events = await recorder.snapshot()
        XCTAssertEqual(events.count, 1)
        let notifiedSession = try XCTUnwrap(events.first ?? nil)
        XCTAssertEqual(notifiedSession.user.email, "signup-success@example.com")
    }

    func testSignInPersistsSessionAndNotifiesListener() async throws {
        let storage = InMemoryAuthStorage()
        let recorder = AuthStateRecorder()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions"
        } response: { request in
            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(queryItems?.first(where: { $0.name == "client_type" })?.value, "mobile")

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["email"] as? String, "signin@example.com")
            XCTAssertEqual(body["password"] as? String, "super-secret")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "signin@example.com",
                    accessToken: "signin-access",
                    refreshToken: "signin-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        await client.setAuthStateChangeListener { session in
            await recorder.record(session)
        }

        let response = try await client.signIn(email: "signin@example.com", password: "super-secret")

        XCTAssertEqual(response.accessToken, "signin-access")

        let persistedSession = try await storage.getSession()
        XCTAssertEqual(persistedSession?.accessToken, "signin-access")

        let events = await recorder.snapshot()
        XCTAssertEqual(events.count, 1)
        let notifiedSession = try XCTUnwrap(events.first ?? nil)
        XCTAssertEqual(notifiedSession.user.email, "signin@example.com")
    }

    func testSignOutClearsSessionAndNotifiesListener() async throws {
        let storage = InMemoryAuthStorage()
        let recorder = AuthStateRecorder()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "signed-in-access",
                refreshToken: "signed-in-refresh",
                email: "signout@example.com"
            )
        )

        let client = AuthTestSupport.makeClient(storage: storage)
        await client.setAuthStateChangeListener { session in
            await recorder.record(session)
        }

        _ = try await client.getAccessToken()
        try await client.signOut()

        let storedSession = try await storage.getSession()
        let currentToken = try await client.getAccessToken()
        XCTAssertNil(storedSession)
        XCTAssertNil(currentToken)

        let events = await recorder.snapshot()
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first!)
    }

    func testGetSessionRestoresCurrentSessionAndNotifiesListener() async throws {
        let storage = InMemoryAuthStorage()
        let recorder = AuthStateRecorder()
        let session = AuthTestSupport.makeSession(
            accessToken: "restored-session-access",
            refreshToken: "restored-session-refresh",
            email: "session@example.com"
        )
        try await storage.saveSession(session)

        let client = AuthTestSupport.makeClient(storage: storage)
        await client.setAuthStateChangeListener { session in
            await recorder.record(session)
        }

        let restoredSession = try await client.getSession()
        XCTAssertEqual(restoredSession?.accessToken, "restored-session-access")

        let restoredToken = try await client.getAccessToken()
        XCTAssertEqual(restoredToken, "restored-session-access")

        let events = await recorder.snapshot()
        XCTAssertEqual(events.count, 1)
        let notifiedSession = try XCTUnwrap(events.first ?? nil)
        XCTAssertEqual(notifiedSession.user.email, "session@example.com")
    }

    func testHandleAuthCallbackUsesPersistedPKCEVerifierAndClearsItAfterExchange() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.savePKCEVerifier("persisted-verifier")

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/oauth/exchange"
        } response: { request in
            XCTAssertEqual(request.httpMethod, "POST")

            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(queryItems?.first(where: { $0.name == "client_type" })?.value, "mobile")

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["code"] as? String, "oauth-code")
            XCTAssertEqual(body["code_verifier"] as? String, "persisted-verifier")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "accessToken": "new-access-token",
                    "refreshToken": "new-refresh-token",
                    "user": AuthTestSupport.makeUserJSON(email: "pkce@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let callbackURL = URL(string: "myapp://auth/callback?insforge_code=oauth-code")!

        let response = try await client.handleAuthCallback(callbackURL)

        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertEqual(response.refreshToken, "new-refresh-token")
        XCTAssertEqual(response.user.email, "pkce@example.com")

        let storedSession = try await storage.getSession()
        XCTAssertEqual(storedSession?.accessToken, "new-access-token")
        XCTAssertEqual(storedSession?.refreshToken, "new-refresh-token")

        let remainingVerifier = try await storage.getPKCEVerifier()
        XCTAssertNil(remainingVerifier)
    }

    func testHandleAuthCallbackLegacyTokenFlowPersistsSessionWithoutNetworkExchange() async throws {
        let storage = InMemoryAuthStorage()
        let client = AuthTestSupport.makeClient(storage: storage)
        let callbackURL = URL(
            string: "myapp://auth/callback?access_token=legacy-access&refresh_token=legacy-refresh&user_id=user-123&email=legacy@example.com"
        )!

        let response = try await client.handleAuthCallback(callbackURL)

        XCTAssertEqual(response.accessToken, "legacy-access")
        XCTAssertEqual(response.refreshToken, "legacy-refresh")
        XCTAssertEqual(response.user.email, "legacy@example.com")

        let persistedSession = try await storage.getSession()
        XCTAssertEqual(persistedSession?.accessToken, "legacy-access")
    }

    func testHandleAuthCallbackWithCodeAndNoPKCEVerifierThrowsInvalidResponse() async throws {
        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        let callbackURL = URL(string: "myapp://auth/callback?insforge_code=missing-verifier")!

        do {
            _ = try await client.handleAuthCallback(callbackURL)
            XCTFail("Expected invalidResponse when PKCE verifier is unavailable")
        } catch let error as InsForgeError {
            switch error {
            case .invalidResponse:
                break
            default:
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.invalidResponse, got \(error)")
        }
    }

    func testHandleAuthCallbackWithoutRequiredParametersThrowsInvalidResponse() async throws {
        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        let callbackURL = URL(string: "myapp://auth/callback?foo=bar")!

        do {
            _ = try await client.handleAuthCallback(callbackURL)
            XCTFail("Expected invalidResponse for callback without auth parameters")
        } catch let error as InsForgeError {
            switch error {
            case .invalidResponse:
                break
            default:
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.invalidResponse, got \(error)")
        }
    }

    func testSendEmailVerificationUsesExpectedEndpointAndPayload() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/send-verification"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["email"] as? String, "verify@example.com")

            return try AuthTestSupport.makeHTTPResponse(url: request.url!, statusCode: 200, json: [:])
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        try await client.sendEmailVerification(email: "verify@example.com")
    }

    func testVerifyEmailWithoutEmailPersistsSession() async throws {
        let storage = InMemoryAuthStorage()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/verify"
        } response: { request in
            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(queryItems?.first(where: { $0.name == "client_type" })?.value, "mobile")

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["otp"] as? String, "123456")
            XCTAssertNil(body["email"])

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "verified@example.com",
                    accessToken: "verified-access",
                    refreshToken: "verified-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let response = try await client.verifyEmail(otp: "123456")

        XCTAssertEqual(response.user.email, "verified@example.com")

        let persistedSession = try await storage.getSession()
        XCTAssertEqual(persistedSession?.refreshToken, "verified-refresh")
    }

    func testVerifyEmailWithExplicitEmailIncludesEmailInRequestPayload() async throws {
        let storage = InMemoryAuthStorage()

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/verify"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["otp"] as? String, "654321")
            XCTAssertEqual(body["email"] as? String, "verified@example.com")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "verified@example.com",
                    accessToken: "verified-access-2",
                    refreshToken: "verified-refresh-2"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let response = try await client.verifyEmail(email: "verified@example.com", otp: "654321")

        XCTAssertEqual(response.user.email, "verified@example.com")

        let persistedSession = try await storage.getSession()
        XCTAssertEqual(persistedSession?.accessToken, "verified-access-2")
    }

    func testGetProfileDecodesProfilePayload() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/profiles/user-123"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "id": "user-123",
                    "profile": [
                        "bio": "Hello, world",
                        "followers": 42
                    ]
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        let profile = try await client.getProfile(userId: "user-123")

        XCTAssertEqual(profile.id, "user-123")
        XCTAssertEqual(profile.profile?["bio"]?.value as? String, "Hello, world")
        XCTAssertEqual(profile.profile?["followers"]?.value as? Int, 42)
    }

    func testUpdateProfileUsesAuthorizationHeaderAndWrappedBody() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "profile-access",
                refreshToken: "profile-refresh",
                email: "profile@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/profiles/current"
        } response: { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer profile-access")

            let body = try AuthTestSupport.decodeJSONBody(request)
            let profile = body["profile"] as? [String: Any]
            XCTAssertEqual(profile?["name"] as? String, "Updated Name")
            XCTAssertEqual(profile?["avatar_url"] as? String, "https://example.com/avatar.png")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "id": "user-123",
                    "profile": [
                        "name": "Updated Name",
                        "avatar_url": "https://example.com/avatar.png"
                    ]
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let updatedProfile = try await client.updateProfile([
            "name": "Updated Name",
            "avatar_url": "https://example.com/avatar.png"
        ])

        XCTAssertEqual(updatedProfile.profile?["name"]?.value as? String, "Updated Name")
    }

    func testSendPasswordResetUsesExpectedEndpointAndPayload() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/send-reset-password"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["email"] as? String, "reset@example.com")

            return try AuthTestSupport.makeHTTPResponse(url: request.url!, statusCode: 200, json: [:])
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        try await client.sendPasswordReset(email: "reset@example.com")
    }

    func testExchangeResetPasswordTokenDecodesTokenAndExpiration() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/exchange-reset-password-token"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["email"] as? String, "reset@example.com")
            XCTAssertEqual(body["code"] as? String, "654321")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "token": "reset-token",
                    "expiresAt": "2026-03-15T12:00:00Z"
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        let response = try await client.exchangeResetPasswordToken(email: "reset@example.com", code: "654321")

        XCTAssertEqual(response.token, "reset-token")
        XCTAssertNotNil(response.expiresAt)
    }

    func testResetPasswordUsesExpectedEndpointAndPayload() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/email/reset-password"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["otp"] as? String, "reset-otp")
            XCTAssertEqual(body["newPassword"] as? String, "new-password")

            return try AuthTestSupport.makeHTTPResponse(url: request.url!, statusCode: 200, json: [:])
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())
        try await client.resetPassword(otp: "reset-otp", newPassword: "new-password")
    }

    func testRefreshAccessTokenPreservesExistingRefreshTokenWhenResponseOmitsReplacement() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-access",
                refreshToken: "stable-refresh-token",
                email: "refresh@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "stable-refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "accessToken": "fresh-access-token",
                    "user": AuthTestSupport.makeUserJSON(email: "refresh@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let response = try await client.refreshAccessToken()

        XCTAssertEqual(response.accessToken, "fresh-access-token")

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "fresh-access-token")
        XCTAssertEqual(updatedSession?.refreshToken, "stable-refresh-token")

        let currentToken = try await client.getAccessToken()
        XCTAssertEqual(currentToken, "fresh-access-token")
    }

    func testRefreshAccessTokenWithoutRefreshTokenThrowsAuthenticationRequired() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "access-only",
                refreshToken: nil,
                email: "norefresh@example.com"
            )
        )

        let client = AuthTestSupport.makeClient(storage: storage)

        do {
            _ = try await client.refreshAccessToken()
            XCTFail("Expected authenticationRequired when no refresh token is stored")
        } catch let error as InsForgeError {
            switch error {
            case .authenticationRequired:
                break
            default:
                XCTFail("Expected authenticationRequired, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.authenticationRequired, got \(error)")
        }

        XCTAssertTrue(MockURLProtocol.snapshotRecordedRequests().isEmpty)
    }

    func testGetCurrentUserRetriesWithRefreshedTokenAfter401() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                email: "before-refresh@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 401,
                json: [
                    "error": "unauthorized",
                    "message": "Token expired"
                ]
            )
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "after-refresh@example.com",
                    accessToken: "fresh-access",
                    refreshToken: "fresh-refresh"
                )
            )
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "user": AuthTestSupport.makeUserJSON(email: "after-refresh@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.email, "after-refresh@example.com")

        let requests = MockURLProtocol.snapshotRecordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/sessions/current", "/refresh", "/sessions/current"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access")

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "fresh-access")
        XCTAssertEqual(updatedSession?.refreshToken, "fresh-refresh")
    }

    func testGetCurrentUserProactivelyRefreshesExpiredJWTAccessTokenBeforeRequest() async throws {
        let expiredAccessToken = try AuthTestSupport.makeJWTAccessToken(
            email: "before-refresh@example.com",
            issuedAt: Date(timeIntervalSince1970: 1_763_000_000),
            expiresAt: Date(timeIntervalSinceNow: -3_600)
        )

        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: expiredAccessToken,
                refreshToken: "refresh-token",
                email: "before-refresh@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expiredAccessToken)"
        } response: { request in
            XCTFail("Expired JWT access token should be refreshed proactively before requesting /sessions/current")
            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 401,
                json: [
                    "error": "unauthorized",
                    "message": "Token expired"
                ]
            )
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "after-refresh@example.com",
                    accessToken: "fresh-access",
                    refreshToken: "fresh-refresh"
                )
            )
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "user": AuthTestSupport.makeUserJSON(email: "after-refresh@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.email, "after-refresh@example.com")

        let requests = MockURLProtocol.snapshotRecordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/refresh", "/sessions/current"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access")

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "fresh-access")
        XCTAssertEqual(updatedSession?.refreshToken, "fresh-refresh")
    }

    func testGetCurrentUserWithValidJWTAccessTokenSkipsProactiveRefresh() async throws {
        let validAccessToken = try AuthTestSupport.makeJWTAccessToken(
            email: "still-valid@example.com",
            issuedAt: Date(timeIntervalSinceNow: -300),
            expiresAt: Date(timeIntervalSinceNow: 3_600)
        )

        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: validAccessToken,
                refreshToken: "refresh-token",
                email: "still-valid@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(validAccessToken)"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "user": AuthTestSupport.makeUserJSON(email: "still-valid@example.com")
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.email, "still-valid@example.com")
        XCTAssertEqual(MockURLProtocol.snapshotRecordedRequests().map { $0.url?.path }, ["/sessions/current"])
    }

    func testConcurrentRefreshAccessTokenCallsShareSingleInFlightRefresh() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "stale-access",
                refreshToken: "stable-refresh-token",
                email: "refresh-race@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "stable-refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "refresh-race@example.com",
                    accessToken: "shared-fresh-access",
                    refreshToken: "shared-fresh-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let callersReady = ConcurrentRequestBarrier(parties: 2)

        let firstTask = Task {
            XCTAssertTrue(callersReady.wait(), "Timed out waiting for the first concurrent refresh caller")
            return try await client.refreshAccessToken()
        }

        let secondTask = Task {
            XCTAssertTrue(callersReady.wait(), "Timed out waiting for the second concurrent refresh caller")
            return try await client.refreshAccessToken()
        }

        let firstResponse = try await firstTask.value
        let secondResponse = try await secondTask.value

        XCTAssertEqual(firstResponse.accessToken, "shared-fresh-access")
        XCTAssertEqual(secondResponse.accessToken, "shared-fresh-access")
        XCTAssertEqual(firstResponse.refreshToken, "shared-fresh-refresh")
        XCTAssertEqual(secondResponse.refreshToken, "shared-fresh-refresh")

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "shared-fresh-access")
        XCTAssertEqual(updatedSession?.refreshToken, "shared-fresh-refresh")

        let requests = MockURLProtocol.snapshotRecordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/refresh"])
    }

    func testRefreshAccessTokenCancellationDoesNotClearSharedInFlightRefreshTask() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "stale-access",
                refreshToken: "rotating-refresh-token",
                email: "refresh-race@example.com"
            )
        )

        let refreshStarted = DispatchSemaphore(value: 0)
        let allowRefreshResponse = DispatchSemaphore(value: 0)

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            refreshStarted.signal()
            XCTAssertEqual(
                allowRefreshResponse.wait(timeout: .now() + 1),
                .success,
                "Timed out waiting to finish the in-flight refresh request"
            )

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "rotating-refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "refresh-race@example.com",
                    accessToken: "shared-fresh-access",
                    refreshToken: "rotated-refresh-token"
                )
            )
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            XCTFail("Cancellation of the first waiter should not allow a second /refresh request to start")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "refresh-race@example.com",
                    accessToken: "unexpected-access",
                    refreshToken: "unexpected-refresh"
                )
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)

        let firstTask = Task {
            try await client.refreshAccessToken()
        }

        XCTAssertEqual(
            refreshStarted.wait(timeout: .now() + 1),
            .success,
            "Timed out waiting for the first refresh request to start"
        )

        firstTask.cancel()
        await Task.yield()

        let secondTask = Task {
            try await client.refreshAccessToken()
        }

        allowRefreshResponse.signal()

        let secondResponse = try await secondTask.value
        _ = await firstTask.result

        XCTAssertEqual(secondResponse.accessToken, "shared-fresh-access")
        XCTAssertEqual(secondResponse.refreshToken, "rotated-refresh-token")

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "shared-fresh-access")
        XCTAssertEqual(updatedSession?.refreshToken, "rotated-refresh-token")

        let requests = MockURLProtocol.snapshotRecordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/refresh"])
    }

    func testConcurrentGetCurrentUserRequestsShareRefreshAfter401() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                email: "before-refresh@example.com"
            )
        )

        for _ in 0..<2 {
            MockURLProtocol.enqueueStub { request in
                request.url?.path == "/sessions/current"
                    && request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access"
            } response: { request in
                return try AuthTestSupport.makeHTTPResponse(
                    url: request.url!,
                    statusCode: 401,
                    json: [
                        "error": "unauthorized",
                        "message": "Token expired"
                    ]
                )
            }
        }

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            let deadline = Date().addingTimeInterval(1)
            while MockURLProtocol.snapshotRecordedRequests().filter({
                $0.url?.path == "/sessions/current"
                    && $0.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access"
            }).count < 2 && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }

            let body = try AuthTestSupport.decodeJSONBody(request)
            XCTAssertEqual(body["refresh_token"] as? String, "refresh-token")

            return try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: AuthTestSupport.makeAuthResponseJSON(
                    email: "after-refresh@example.com",
                    accessToken: "fresh-access",
                    refreshToken: "fresh-refresh"
                )
            )
        }

        for _ in 0..<2 {
            MockURLProtocol.enqueueStub { request in
                request.url?.path == "/sessions/current"
                    && request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access"
            } response: { request in
                try AuthTestSupport.makeHTTPResponse(
                    url: request.url!,
                    statusCode: 200,
                    json: [
                        "user": AuthTestSupport.makeUserJSON(email: "after-refresh@example.com")
                    ]
                )
            }
        }

        let client = AuthTestSupport.makeClient(storage: storage)
        let callersReady = ConcurrentRequestBarrier(parties: 2)

        let firstTask = Task {
            XCTAssertTrue(callersReady.wait(), "Timed out waiting for the first concurrent getCurrentUser caller")
            return try await client.getCurrentUser()
        }

        let secondTask = Task {
            XCTAssertTrue(callersReady.wait(), "Timed out waiting for the second concurrent getCurrentUser caller")
            return try await client.getCurrentUser()
        }

        let firstUser = try await firstTask.value
        let secondUser = try await secondTask.value

        XCTAssertEqual(firstUser.email, "after-refresh@example.com")
        XCTAssertEqual(secondUser.email, "after-refresh@example.com")

        let requests = MockURLProtocol.snapshotRecordedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/refresh" }.count, 1)
        XCTAssertEqual(
            requests.filter {
                $0.url?.path == "/sessions/current"
                    && $0.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access"
            }.count,
            2
        )
        XCTAssertEqual(
            requests.filter {
                $0.url?.path == "/sessions/current"
                    && $0.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access"
            }.count,
            2
        )

        let updatedSession = try await storage.getSession()
        XCTAssertEqual(updatedSession?.accessToken, "fresh-access")
        XCTAssertEqual(updatedSession?.refreshToken, "fresh-refresh")
    }

    func testGetCurrentUserWithAutoRefreshDisabledPropagates401WithoutRefreshAttempt() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                email: "disabled-refresh@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions/current"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 401,
                json: [
                    "error": "unauthorized",
                    "message": "Token expired"
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage, autoRefreshToken: false)

        do {
            _ = try await client.getCurrentUser()
            XCTFail("Expected the original 401 to be propagated when auto refresh is disabled")
        } catch let error as InsForgeError {
            switch error {
            case .httpError(let statusCode, let message, _, _):
                XCTAssertEqual(statusCode, 401)
                XCTAssertEqual(message, "Token expired")
            default:
                XCTFail("Expected original 401 error, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.httpError, got \(error)")
        }

        XCTAssertEqual(MockURLProtocol.snapshotRecordedRequests().map { $0.url?.path }, ["/sessions/current"])
    }

    func testUpdateProfileWithAutoRefreshDisabledPropagates401WithoutRefreshAttempt() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-profile-access",
                refreshToken: "profile-refresh",
                email: "profile-disabled@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/profiles/current"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 401,
                json: [
                    "error": "unauthorized",
                    "message": "Token expired"
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage, autoRefreshToken: false)

        do {
            _ = try await client.updateProfile(["name": "Should Fail"])
            XCTFail("Expected the original 401 to be propagated when auto refresh is disabled")
        } catch let error as InsForgeError {
            switch error {
            case .httpError(let statusCode, let message, _, _):
                XCTAssertEqual(statusCode, 401)
                XCTAssertEqual(message, "Token expired")
            default:
                XCTFail("Expected original 401 error, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.httpError, got \(error)")
        }

        XCTAssertEqual(MockURLProtocol.snapshotRecordedRequests().map { $0.url?.path }, ["/profiles/current"])
    }

    func testRefreshAccessTokenClearsStoredSessionWhenRefreshTokenIsRejected() async throws {
        let storage = InMemoryAuthStorage()
        try await storage.saveSession(
            AuthTestSupport.makeSession(
                accessToken: "expired-access",
                refreshToken: "expired-refresh",
                email: "expired@example.com"
            )
        )

        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/refresh"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 401,
                json: [
                    "error": "unauthorized",
                    "message": "Refresh token expired"
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: storage)

        do {
            _ = try await client.refreshAccessToken()
            XCTFail("Expected token refresh rejection to require re-authentication")
        } catch let error as InsForgeError {
            switch error {
            case .authenticationRequired:
                break
            default:
                XCTFail("Expected authenticationRequired, got \(error)")
            }
        } catch {
            XCTFail("Expected InsForgeError.authenticationRequired, got \(error)")
        }

        let clearedSession = try await storage.getSession()
        let clearedToken = try await client.getAccessToken()
        XCTAssertNil(clearedSession)
        XCTAssertNil(clearedToken)
    }

    func testSignInWithMalformedSuccessPayloadThrowsDecodingError() async throws {
        MockURLProtocol.enqueueStub { request in
            request.url?.path == "/sessions"
        } response: { request in
            try AuthTestSupport.makeHTTPResponse(
                url: request.url!,
                statusCode: 200,
                json: [
                    "accessToken": "broken-access"
                ]
            )
        }

        let client = AuthTestSupport.makeClient(storage: InMemoryAuthStorage())

        do {
            _ = try await client.signIn(email: "broken@example.com", password: "super-secret")
            XCTFail("Expected malformed payload to surface as a decoding error")
        } catch is DecodingError {
            // Expected.
        } catch {
            XCTFail("Expected DecodingError, got \(error)")
        }
    }
}
