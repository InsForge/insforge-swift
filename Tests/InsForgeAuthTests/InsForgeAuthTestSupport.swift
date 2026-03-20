import Foundation
import XCTest
@testable import InsForgeAuth
@testable import InsForgeCore

enum AuthTestSupport {
    private static let baseURL = URL(string: "https://example.com")!
    private static let authComponentURL = URL(string: "https://example.com/auth")!
    private static let defaultHeaders = ["X-Client-Info": "insforge-swift-tests"]

    static func makeClient(
        storage: AuthStorage,
        autoRefreshToken: Bool = true
    ) -> AuthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let httpClient = HTTPClient(session: session)

        return AuthClient(
            url: baseURL,
            authComponent: authComponentURL,
            headers: defaultHeaders,
            httpClient: httpClient,
            options: AuthOptions(
                autoRefreshToken: autoRefreshToken,
                storage: storage
            )
        )
    }

    static func makeSession(
        accessToken: String,
        refreshToken: String?,
        email: String
    ) -> Session {
        Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: User(
                id: UUID().uuidString,
                email: email,
                emailVerified: true,
                profile: UserProfile(name: "Test User", avatarUrl: nil),
                metadata: nil,
                identities: [Identity(provider: "email")],
                providerType: "email",
                role: "authenticated",
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }

    static func decodeJSONBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try requestBodyData(from: request)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    static func makeUserJSON(email: String) -> [String: Any] {
        [
            "id": UUID().uuidString,
            "email": email,
            "emailVerified": true,
            "identities": [["provider": "email"]],
            "providerType": "email",
            "role": "authenticated",
            "createdAt": "2026-03-15T12:00:00Z",
            "updatedAt": "2026-03-15T12:00:00Z"
        ]
    }

    static func makeAuthResponseJSON(
        email: String,
        accessToken: String,
        refreshToken: String?
    ) -> [String: Any] {
        var json: [String: Any] = [
            "user": makeUserJSON(email: email),
            "accessToken": accessToken
        ]
        if let refreshToken {
            json["refreshToken"] = refreshToken
        }
        return json
    }

    static func makeJWTAccessToken(
        subject: String = UUID().uuidString,
        email: String = "jwt@example.com",
        issuedAt: Date = Date(),
        expiresAt: Date
    ) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: [
            "alg": "HS256",
            "typ": "JWT"
        ])
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject,
            "email": email,
            "role": "authenticated",
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(expiresAt.timeIntervalSince1970)
        ])

        let signature = Data("test-signature".utf8)
        return [
            header.base64URLEncodedString(),
            payload.base64URLEncodedString(),
            signature.base64URLEncodedString()
        ].joined(separator: ".")
    }

    static func makeHTTPResponse(
        url: URL,
        statusCode: Int,
        json: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, data)
    }

    private static func requestBodyData(from request: URLRequest) throws -> Data {
        if let data = request.httpBody {
            return data
        }

        guard let stream = request.httpBodyStream else {
            XCTFail("Expected request body data for \(String(describing: request.url))")
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw stream.streamError ?? InsForgeError.invalidResponse
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

actor AuthStateRecorder {
    private var events = [Session?]()

    func record(_ session: Session?) {
        events.append(session)
    }

    func snapshot() -> [Session?] {
        events
    }
}

final class ConcurrentRequestBarrier: @unchecked Sendable {
    private let parties: Int
    private let condition = NSCondition()
    private var arrivals = 0

    init(parties: Int) {
        self.parties = parties
    }

    @discardableResult
    func wait(timeout: TimeInterval = 5.0) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        arrivals += 1
        if arrivals >= parties {
            condition.broadcast()
            return true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while arrivals < parties {
            if !condition.wait(until: deadline) {
                return false
            }
        }

        return true
    }
}

final class MockURLProtocol: URLProtocol {
    struct Stub {
        let matches: (URLRequest) -> Bool
        let response: (URLRequest) throws -> (HTTPURLResponse, Data)
    }

    private static let lock = NSLock()
    private static var stubs = [Stub]()
    private(set) static var recordedRequests = [URLRequest]()

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub?

        Self.lock.lock()
        Self.recordedRequests.append(request)
        if let index = Self.stubs.firstIndex(where: { $0.matches(request) }) {
            stub = Self.stubs.remove(at: index)
        } else {
            stub = nil
        }
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 1))
            XCTFail("No stub registered for request: \(request)")
            return
        }

        do {
            let (response, data) = try stub.response(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func enqueueStub(
        matching: @escaping (URLRequest) -> Bool,
        response: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        stubs.append(Stub(matches: matching, response: response))
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        stubs.removeAll()
        recordedRequests.removeAll()
        lock.unlock()
    }

    static func snapshotRecordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}
