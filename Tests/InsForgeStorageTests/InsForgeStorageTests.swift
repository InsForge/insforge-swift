import XCTest
@testable import InsForgeStorage
@testable import InsForgeCore

final class InsForgeStorageTests: XCTestCase {
    func testStoredFileDecoding() throws {
        let json = """
        {
            "bucket": "avatars",
            "key": "user123.jpg",
            "size": 102400,
            "mimeType": "image/jpeg",
            "uploadedAt": "2025-01-01T00:00:00Z",
            "url": "/api/storage/buckets/avatars/objects/user123.jpg"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let file = try decoder.decode(StoredFile.self, from: data)

        XCTAssertEqual(file.bucket, "avatars")
        XCTAssertEqual(file.key, "user123.jpg")
        XCTAssertEqual(file.size, 102400)
        XCTAssertEqual(file.mimeType, "image/jpeg")
        XCTAssertEqual(file.url, "/api/storage/buckets/avatars/objects/user123.jpg")
    }
}
