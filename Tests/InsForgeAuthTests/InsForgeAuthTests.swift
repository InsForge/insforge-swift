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

}
