import XCTest
@testable import InsForge
@testable import InsForgeStorage
@testable import InsForgeCore

/// Tests for InsForge Storage Client
///
/// ## Setup Instructions
/// These tests will create a test bucket named 'test-bucket-swift-sdk' and perform file operations.
/// The bucket will be cleaned up after tests complete.
///
/// ## What's tested:
/// - List buckets
/// - Create bucket
/// - Upload files (with auto-generated key and specific key)
/// - List files in bucket
/// - Download files
/// - Delete files
/// - Delete bucket
final class InsForgeStorageTests: XCTestCase {
    // MARK: - Configuration

    /// Your InsForge instance URL
    private let insForgeURL = "https://pg6afqz9.us-east.insforge.app"

    /// Your InsForge API key
    private let apiKey = "ik_ca177fcf1e2e72e8d1e0c2c23dbe3b79"

    /// Test bucket name (will be created and deleted during tests)
    private let testBucketName = "test-bucket-swift-sdk"

    // MARK: - Helper

    private var insForgeClient: InsForgeClient!

    override func setUp() async throws {
        insForgeClient = InsForgeClient(
            insForgeURL: URL(string: insForgeURL)!,
            apiKey: apiKey
        )
        print("📍 InsForge URL: \(insForgeURL)")
    }

    override func tearDown() async throws {
        // Clean up test bucket if it exists
        do {
            try await insForgeClient.storage.deleteBucket(testBucketName)
            print("🧹 Cleaned up test bucket: \(testBucketName)")
        } catch {
            // Ignore errors if bucket doesn't exist
            print("ℹ️ No cleanup needed or cleanup failed: \(error)")
        }

        insForgeClient = nil
    }

    // MARK: - Tests

    func testStorageClientInitialization() async {
        let storageClient = await insForgeClient.storage
        XCTAssertNotNil(storageClient)
    }

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

    /// Test listing buckets
    func testListBuckets() async throws {
        print("🔵 Testing listBuckets...")

        let buckets = try await insForgeClient.storage.listBuckets()

        XCTAssertNotNil(buckets)
        print("✅ Found \(buckets.count) bucket(s): \(buckets)")
    }

    /// Test creating a bucket
    func testCreateBucket() async throws {
        print("🔵 Testing createBucket...")

        // Delete if already exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)

        // Create bucket
        try await insForgeClient.storage.createBucket(
            name: testBucketName,
            isPublic: true
        )

        // Verify it exists
        let buckets = try await insForgeClient.storage.listBuckets()
        XCTAssertTrue(buckets.contains(testBucketName),
                     "Created bucket should appear in bucket list")

        print("✅ Successfully created bucket: \(testBucketName)")
    }

    /// Test uploading a file with auto-generated key
    /// NOTE: Auto-key upload may not be supported by all InsForge instances
    func testUploadFileWithAutoKey() async throws {
        print("🔵 Testing bucket.upload (auto-generated key)...")

        // Ensure bucket exists
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        // Create test file
        let testContent = "Hello from Swift SDK - Auto Key".data(using: .utf8)!
        let fileName = "test-auto-\(UUID().uuidString).txt"

        // Upload file
        let bucket = await insForgeClient.storage.bucket(testBucketName)

        do {
            let uploadedFile = try await bucket.upload(
                file: testContent,
                fileName: fileName,
                mimeType: "text/plain"
            )

            // Verify
            XCTAssertEqual(uploadedFile.bucket, testBucketName)
            XCTAssertFalse(uploadedFile.key.isEmpty)
            XCTAssertEqual(uploadedFile.size, testContent.count)
            XCTAssertEqual(uploadedFile.mimeType, "text/plain")

            print("✅ Uploaded file: \(uploadedFile.key), size: \(uploadedFile.size) bytes")
        } catch let error as InsForgeError {
            if case .httpError(let statusCode, _, _, _) = error, statusCode == 404 {
                throw XCTSkip("Auto-key upload not supported by this InsForge instance")
            } else {
                throw error
            }
        }
    }

    /// Test uploading a file with specific key
    func testUploadFileWithSpecificKey() async throws {
        print("🔵 Testing bucket.upload (specific key)...")

        // Ensure bucket exists
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        // Create test file
        let testContent = "Hello from Swift SDK - Specific Key".data(using: .utf8)!
        let fileKey = "test-files/specific-\(UUID().uuidString).txt"

        // Upload file
        let bucket = await insForgeClient.storage.bucket(testBucketName)
        let uploadedFile = try await bucket.upload(
            file: testContent,
            key: fileKey,
            mimeType: "text/plain"
        )

        // Verify
        XCTAssertEqual(uploadedFile.bucket, testBucketName)
        XCTAssertEqual(uploadedFile.key, fileKey)
        XCTAssertEqual(uploadedFile.size, testContent.count)

        print("✅ Uploaded file with key: \(uploadedFile.key)")
    }

    /// Test listing files in bucket
    func testListFiles() async throws {
        print("🔵 Testing bucket.list...")

        // Ensure bucket exists and has files
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        let bucket = await insForgeClient.storage.bucket(testBucketName)

        // Upload a test file first (use key, not fileName)
        let testContent = "Test content for listing".data(using: .utf8)!
        _ = try await bucket.upload(
            file: testContent,
            key: "test-list-\(UUID().uuidString).txt",
            mimeType: "text/plain"
        )

        // List files
        let files = try await bucket.list()

        XCTAssertNotNil(files)
        XCTAssertFalse(files.isEmpty, "Bucket should contain at least one file")

        print("✅ Listed \(files.count) file(s) in bucket")
        for file in files.prefix(5) {
            print("   - \(file.key) (\(file.size) bytes)")
        }
    }

    /// Test listing files with prefix filter
    func testListFilesWithPrefix() async throws {
        print("🔵 Testing bucket.list with prefix...")

        // Ensure bucket exists
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        let bucket = await insForgeClient.storage.bucket(testBucketName)

        // Upload files with specific prefix
        let prefix = "test-prefix-\(UUID().uuidString)"
        let testContent = "Test content".data(using: .utf8)!

        _ = try await bucket.upload(
            file: testContent,
            key: "\(prefix)/file1.txt",
            mimeType: "text/plain"
        )
        _ = try await bucket.upload(
            file: testContent,
            key: "\(prefix)/file2.txt",
            mimeType: "text/plain"
        )

        // List with prefix
        let files = try await bucket.list(prefix: prefix, limit: 10)

        XCTAssertEqual(files.count, 2, "Should find exactly 2 files with the prefix")
        XCTAssertTrue(files.allSatisfy { $0.key.hasPrefix(prefix) })

        print("✅ Found \(files.count) file(s) with prefix '\(prefix)'")
    }

    /// Test downloading a file
    func testDownloadFile() async throws {
        print("🔵 Testing bucket.download...")

        // Ensure bucket exists
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        let bucket = await insForgeClient.storage.bucket(testBucketName)

        // Upload a file first
        let originalContent = "Hello from Swift SDK - Download Test".data(using: .utf8)!
        let fileKey = "test-download-\(UUID().uuidString).txt"

        _ = try await bucket.upload(
            file: originalContent,
            key: fileKey,
            mimeType: "text/plain"
        )

        // Download the file
        let downloadedData = try await bucket.download(key: fileKey)

        // Verify content matches
        XCTAssertEqual(downloadedData, originalContent)

        let downloadedString = String(data: downloadedData, encoding: .utf8)
        print("✅ Downloaded file: \(fileKey)")
        print("   Content: \(downloadedString ?? "unable to decode")")
    }

    /// Test getting public URL
    func testGetPublicURL() async {
        print("🔵 Testing bucket.getPublicURL...")

        let bucket = await insForgeClient.storage.bucket(testBucketName)
        let fileKey = "test-files/public-test.jpg"

        let publicURL = bucket.getPublicURL(key: fileKey)

        XCTAssertTrue(publicURL.absoluteString.contains(testBucketName))
        XCTAssertTrue(publicURL.absoluteString.contains(fileKey))

        print("✅ Generated public URL: \(publicURL.absoluteString)")
    }

    /// Test deleting a file
    func testDeleteFile() async throws {
        print("🔵 Testing bucket.delete...")

        // Ensure bucket exists
        try? await insForgeClient.storage.createBucket(name: testBucketName, isPublic: true)

        let bucket = await insForgeClient.storage.bucket(testBucketName)

        // Upload a file first
        let testContent = "To be deleted".data(using: .utf8)!
        let fileKey = "test-delete-\(UUID().uuidString).txt"

        _ = try await bucket.upload(
            file: testContent,
            key: fileKey,
            mimeType: "text/plain"
        )

        // Delete the file
        try await bucket.delete(key: fileKey)

        // Verify it's gone by trying to download (should fail)
        do {
            _ = try await bucket.download(key: fileKey)
            XCTFail("Download should fail after deletion")
        } catch {
            // Expected to fail
            print("✅ Successfully deleted file: \(fileKey)")
        }
    }

    /// Test deleting a bucket
    func testDeleteBucket() async throws {
        print("🔵 Testing deleteBucket...")

        // Create a temporary bucket
        let tempBucket = "temp-bucket-\(UUID().uuidString)"
        try await insForgeClient.storage.createBucket(name: tempBucket, isPublic: true)

        // Verify it exists
        var buckets = try await insForgeClient.storage.listBuckets()
        XCTAssertTrue(buckets.contains(tempBucket))

        // Delete it
        try await insForgeClient.storage.deleteBucket(tempBucket)

        // Verify it's gone
        buckets = try await insForgeClient.storage.listBuckets()
        XCTAssertFalse(buckets.contains(tempBucket))

        print("✅ Successfully deleted bucket: \(tempBucket)")
    }

    /// Test complete workflow: create bucket -> upload -> list -> download -> delete -> delete bucket
    func testCompleteWorkflow() async throws {
        print("🔵 Testing complete storage workflow...")

        let workflowBucket = "workflow-test-\(UUID().uuidString)"

        // 1. Create bucket
        try await insForgeClient.storage.createBucket(name: workflowBucket, isPublic: true)
        print("   ✓ Created bucket")

        let bucket = await insForgeClient.storage.bucket(workflowBucket)

        // 2. Upload file
        let content = "Workflow test content".data(using: .utf8)!
        let fileKey = "workflow-test.txt"
        let uploaded = try await bucket.upload(
            file: content,
            key: fileKey,
            mimeType: "text/plain"
        )
        print("   ✓ Uploaded file: \(uploaded.key)")

        // 3. List files
        let files = try await bucket.list()
        XCTAssertEqual(files.count, 1)
        print("   ✓ Listed files: \(files.count)")

        // 4. Download file
        let downloaded = try await bucket.download(key: fileKey)
        XCTAssertEqual(downloaded, content)
        print("   ✓ Downloaded and verified content")

        // 5. Delete file
        try await bucket.delete(key: fileKey)
        print("   ✓ Deleted file")

        // 6. Delete bucket
        try await insForgeClient.storage.deleteBucket(workflowBucket)
        print("   ✓ Deleted bucket")

        print("✅ Complete workflow successful!")
    }
}
