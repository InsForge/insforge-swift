import XCTest
@testable import InsForgeCore

// MARK: - Mock URLSession

/// A `URLProtocol` subclass that serves canned responses for unit tests.
private final class MockURLProtocol: URLProtocol {
    /// Set this before each test to control what response the mock returns.
    static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.responseHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headers
    )!
}

private func emptyData() -> Data { Data() }

private func errorJSON(_ message: String = "error") -> Data {
    (try? JSONEncoder().encode(["message": message, "error": "test_error"])) ?? Data()
}

// MARK: - NetworkError Tests

final class NetworkErrorTests: XCTestCase {

    // MARK: from(_:) mapping

    func testTimeoutMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        if case .timeout = NetworkError.from(error) {
        } else {
            XCTFail("Expected .timeout, got \(NetworkError.from(error))")
        }
    }

    func testNoNetworkMapping_notConnected() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        if case .noNetwork = NetworkError.from(error) {
        } else {
            XCTFail("Expected .noNetwork")
        }
    }

    func testNoNetworkMapping_connectionLost() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        if case .noNetwork = NetworkError.from(error) {
        } else {
            XCTFail("Expected .noNetwork for connection-lost")
        }
    }

    func testCancelledMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        if case .cancelled = NetworkError.from(error) {
        } else {
            XCTFail("Expected .cancelled")
        }
    }

    func testSSLErrorMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        if case .sslError = NetworkError.from(error) {
        } else {
            XCTFail("Expected .sslError")
        }
    }

    func testCannotConnectMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        if case .cannotConnect = NetworkError.from(error) {
        } else {
            XCTFail("Expected .cannotConnect")
        }
    }

    func testOtherMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown)
        if case .other = NetworkError.from(error) {
        } else {
            XCTFail("Expected .other for unknown NSURLError code")
        }
    }

    // MARK: errorDescription

    func testTimeoutDescription() {
        XCTAssertEqual(NetworkError.timeout.errorDescription, "The request timed out")
    }

    func testNoNetworkDescription() {
        XCTAssertEqual(NetworkError.noNetwork.errorDescription, "No network connection available")
    }

    func testCancelledDescription() {
        XCTAssertEqual(NetworkError.cancelled.errorDescription, "The request was cancelled")
    }
}

// MARK: - RetryConfiguration Tests

final class RetryConfigurationTests: XCTestCase {

    func testDefaultValues() {
        let config = RetryConfiguration.default
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.baseDelay, 0.5)
        XCTAssertEqual(config.maxDelay, 30)
        XCTAssertTrue(config.useJitter)
    }

    func testDisabledHasZeroRetries() {
        XCTAssertEqual(RetryConfiguration.disabled.maxRetries, 0)
    }

    func testNegativeMaxRetriesClampedToZero() {
        let config = RetryConfiguration(maxRetries: -5)
        XCTAssertEqual(config.maxRetries, 0)
    }

    func testDelayGrowsExponentially() {
        let config = RetryConfiguration(maxRetries: 3, baseDelay: 1.0, maxDelay: 60, useJitter: false)
        XCTAssertEqual(config.delay(for: 0), 1.0, accuracy: 0.001)  // 1 * 2^0
        XCTAssertEqual(config.delay(for: 1), 2.0, accuracy: 0.001)  // 1 * 2^1
        XCTAssertEqual(config.delay(for: 2), 4.0, accuracy: 0.001)  // 1 * 2^2
    }

    func testDelayIsCappedAtMaxDelay() {
        let config = RetryConfiguration(maxRetries: 10, baseDelay: 1.0, maxDelay: 5.0, useJitter: false)
        XCTAssertLessThanOrEqual(config.delay(for: 5), 5.0)
        XCTAssertLessThanOrEqual(config.delay(for: 9), 5.0)
    }

    func testJitterAddsSmallPositiveValue() {
        // With jitter the delay should be >= the base value and <= base + 10% jitter
        let config = RetryConfiguration(maxRetries: 3, baseDelay: 1.0, maxDelay: 60, useJitter: true)
        let delay = config.delay(for: 0)  // exponential = 1.0
        XCTAssertGreaterThanOrEqual(delay, 1.0)
        XCTAssertLessThanOrEqual(delay, 1.1 + 0.001)
    }
}

// MARK: - HTTPClient Retry Tests

final class HTTPClientRetryTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        session = makeMockSession()
        MockURLProtocol.responseHandler = nil
    }

    // MARK: 5xx retry

    func testFiveXXIsRetriedUpToMaxRetries() async throws {
        var callCount = 0
        // Always return 503
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            return (makeResponse(statusCode: 503), emptyData())
        }

        let config = RetryConfiguration(maxRetries: 2, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected httpError to be thrown")
        } catch let error as InsForgeError {
            if case .httpError(let code, _, _, _) = error {
                XCTAssertEqual(code, 503)
            } else {
                XCTFail("Expected httpError(503), got \(error)")
            }
        }
        // 1 initial + 2 retries
        XCTAssertEqual(callCount, 3)
    }

    func testFiveXXSucceedsAfterOneRetry() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return (makeResponse(statusCode: 500), emptyData())
            }
            return (makeResponse(statusCode: 200), Data("{}".utf8))
        }

        let config = RetryConfiguration(maxRetries: 2, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)
        let response = try await client.execute(.get, url: URL(string: "https://example.com")!)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(callCount, 2)
    }

    // MARK: 429 retry

    func testFourTwentyNineIsRetried() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return (makeResponse(statusCode: 429, headers: ["Retry-After": "0"]), emptyData())
            }
            return (makeResponse(statusCode: 200), Data("{}".utf8))
        }

        let config = RetryConfiguration(maxRetries: 2, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)
        let response = try await client.execute(.get, url: URL(string: "https://example.com")!)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(callCount, 2)
    }

    // MARK: non-retryable errors

    func testNoNetworkIsNotRetried() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        let config = RetryConfiguration(maxRetries: 3, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch let error as InsForgeError {
            if case .networkError(let netErr) = error, case .noNetwork = netErr {
                // correct
            } else {
                XCTFail("Expected networkError(.noNetwork), got \(error)")
            }
        }
        // Should not retry
        XCTAssertEqual(callCount, 1)
    }

    func testCancelledIsNotRetried() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        }

        let config = RetryConfiguration(maxRetries: 3, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch let error as InsForgeError {
            if case .networkError(let netErr) = error, case .cancelled = netErr {
                // correct
            } else {
                XCTFail("Expected networkError(.cancelled), got \(error)")
            }
        }
        XCTAssertEqual(callCount, 1)
    }

    func testFourXXIsNotRetried() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            return (makeResponse(statusCode: 400), emptyData())
        }

        let config = RetryConfiguration(maxRetries: 3, baseDelay: 0, maxDelay: 0, useJitter: false)
        let client = HTTPClient(session: session, retry: config)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch let error as InsForgeError {
            if case .httpError(400, _, _, _) = error {
                // correct
            } else {
                XCTFail("Expected httpError(400), got \(error)")
            }
        }
        XCTAssertEqual(callCount, 1)
    }

    // MARK: disabled retry

    func testDisabledRetryNeverRetries() async throws {
        var callCount = 0
        MockURLProtocol.responseHandler = { _ in
            callCount += 1
            return (makeResponse(statusCode: 503), emptyData())
        }

        let client = HTTPClient(session: session, retry: .disabled)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch {}

        XCTAssertEqual(callCount, 1)
    }

    // MARK: timeout maps to NetworkError

    func testTimeoutMapsToNetworkErrorTimeout() async throws {
        MockURLProtocol.responseHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        }

        let client = HTTPClient(session: session, retry: .disabled)

        do {
            _ = try await client.execute(.get, url: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch let error as InsForgeError {
            if case .networkError(let netErr) = error, case .timeout = netErr {
                // correct
            } else {
                XCTFail("Expected networkError(.timeout), got \(error)")
            }
        }
    }
}
