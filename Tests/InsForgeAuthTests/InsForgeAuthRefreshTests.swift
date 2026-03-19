import Foundation
import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

final class InsForgeAuthRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
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
