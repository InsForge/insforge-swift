import Foundation
import XCTest
@testable import InsForgeCore
@testable import InsForgeStorage

final class StorageChunkedUploadTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testUploadFromFileURLUsesStreamedMultipartBodyForPresignedUploads() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let httpClient = HTTPClient(session: session)
        let headers = LockIsolated(["Authorization": "Bearer test-token"])
        let fileApi = StorageFileApi(
            bucketId: "large-files",
            url: URL(string: "https://api.example.com/api/storage")!,
            headersProvider: headers,
            httpClient: httpClient
        )

        let sourceData = Data(repeating: 0x41, count: 4096) + Data("chunked-upload".utf8)
        let sourceFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunked-upload-\(UUID().uuidString).txt")
        try sourceData.write(to: sourceFileURL)
        defer { try? FileManager.default.removeItem(at: sourceFileURL) }

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw InsForgeError.invalidURL
            }

            switch url.absoluteString {
            case "https://api.example.com/api/storage/buckets/large-files/upload-strategy":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                    "method": "presigned",
                    "uploadUrl": "https://uploads.example.com/presigned",
                    "fields": {
                        "key": "uploads/large-file.txt",
                        "policy": "policy-token"
                    },
                    "key": "uploads/large-file.txt",
                    "confirmRequired": true,
                    "confirmUrl": "/api/storage/buckets/large-files/objects/uploads/large-file.txt/confirm-upload"
                }
                """.data(using: .utf8)!
                return (response, body)
            case "https://uploads.example.com/presigned":
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"etag-123\""]
                )!
                return (response, Data())
            default:
                if url.absoluteString.contains("/confirm-upload") {
                    let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!
                    let body = """
                    {
                        "bucket": "large-files",
                        "key": "uploads/large-file.txt",
                        "size": \(sourceData.count),
                        "mimeType": "text/plain",
                        "uploadedAt": "2025-01-01T00:00:00Z",
                        "url": "https://cdn.example.com/uploads/large-file.txt"
                    }
                    """.data(using: .utf8)!
                    return (response, body)
                }

                throw InsForgeError.unknown("Unexpected request: \(url.absoluteString)")
            }
        }

        let storedFile = try await fileApi.upload(
            path: "uploads/large-file.txt",
            fileURL: sourceFileURL,
            options: FileOptions(contentType: "text/plain", multipartChunkSize: 17)
        )

        XCTAssertEqual(storedFile.bucket, "large-files")
        XCTAssertEqual(storedFile.key, "uploads/large-file.txt")

        let capturedRequests = MockURLProtocol.capturedRequests
        XCTAssertEqual(capturedRequests.count, 3)

        let strategyRequest = try XCTUnwrap(capturedRequests.first { $0.url.absoluteString.hasSuffix("/upload-strategy") })
        let strategyJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: strategyRequest.body) as? [String: Any]
        )
        XCTAssertEqual(strategyJSON["filename"] as? String, "uploads/large-file.txt")
        XCTAssertEqual(strategyJSON["contentType"] as? String, "text/plain")
        XCTAssertEqual(strategyJSON["size"] as? Int, sourceData.count)

        let uploadRequest = try XCTUnwrap(capturedRequests.first { $0.url.absoluteString == "https://uploads.example.com/presigned" })
        XCTAssertNil(uploadRequest.request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(uploadRequest.request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data; boundary=") == true)

        let uploadBodyString = try XCTUnwrap(String(data: uploadRequest.body, encoding: .utf8))
        XCTAssertTrue(uploadBodyString.contains("name=\"key\"\r\n\r\nuploads/large-file.txt"))
        XCTAssertTrue(uploadBodyString.contains("name=\"policy\"\r\n\r\npolicy-token"))
        XCTAssertTrue(uploadBodyString.contains("filename=\"large-file.txt\""))
        XCTAssertTrue(uploadBodyString.contains("chunked-upload"))

        let confirmRequest = try XCTUnwrap(capturedRequests.first { $0.url.absoluteString.contains("/confirm-upload") })
        let confirmJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: confirmRequest.body) as? [String: Any]
        )
        XCTAssertEqual(confirmJSON["size"] as? Int, sourceData.count)
        XCTAssertEqual(confirmJSON["contentType"] as? String, "text/plain")
        XCTAssertEqual(confirmJSON["etag"] as? String, "etag-123")
    }

    func testMultipartBodyFileRejectsInvalidChunkSizes() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-chunk-\(UUID().uuidString).txt")
        try Data("content".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(
            try MultipartFormBodyFile.create(
                formFields: [:],
                sourceFileURL: fileURL,
                fileName: "invalid.txt",
                mimeType: "text/plain",
                chunkSize: 0
            )
        ) { error in
            guard case InsForgeError.validationError(let message) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }

            XCTAssertEqual(message, "Chunk size must be greater than 0")
        }
    }
}

private struct CapturedRequest {
    let url: URL
    let request: URLRequest
    let body: Data
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    private static var storage = LockIsolated<[CapturedRequest]>([])

    static var capturedRequests: [CapturedRequest] {
        storage.value
    }

    static func reset() {
        requestHandler = nil
        storage.setValue([])
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: InsForgeError.unknown("Missing request handler"))
            return
        }

        do {
            let body = Self.bodyData(from: request)
            if let url = request.url {
                Self.storage.withValue { requests in
                    requests.append(CapturedRequest(url: url, request: request, body: body))
                }
            }

            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }

        return data
    }
}
