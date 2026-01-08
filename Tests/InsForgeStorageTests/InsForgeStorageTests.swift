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
/// - Update bucket
/// - Upload files (with specific key and auto-generated key)
/// - List files in bucket
/// - Download files
/// - Delete files
/// - Delete bucket
/// - Upload/Download strategies (for S3 presigned URLs)
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
            baseURL: URL(string: insForgeURL)!,
            anonKey: apiKey
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
            "key": "users/user123.jpg",
            "size": 12345,
            "mimeType": "image/jpeg",
            "uploadedAt": "2025-01-01T00:00:00Z",
            "url": "https://storage.insforge.com/avatars/users/user123.jpg"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let file = try decoder.decode(StoredFile.self, from: data)

        XCTAssertEqual(file.bucket, "avatars")
        XCTAssertEqual(file.key, "users/user123.jpg")
        XCTAssertEqual(file.size, 12345)
        XCTAssertEqual(file.mimeType, "image/jpeg")
    }

    func testUploadStrategyDecoding() throws {
        let json = """
        {
            "method": "presigned",
            "uploadUrl": "https://s3.amazonaws.com/bucket/...",
            "fields": {"key": "value"},
            "key": "users/avatar.jpg",
            "confirmRequired": true,
            "confirmUrl": "https://api.insforge.com/storage/confirm",
            "expiresAt": "2025-01-01T01:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let strategy = try decoder.decode(UploadStrategy.self, from: data)

        XCTAssertEqual(strategy.method, "presigned")
        XCTAssertEqual(strategy.key, "users/avatar.jpg")
        XCTAssertTrue(strategy.confirmRequired)
        XCTAssertNotNil(strategy.fields)
    }

    func testDownloadStrategyDecoding() throws {
        let json = """
        {
            "method": "presigned",
            "url": "https://s3.amazonaws.com/bucket/...",
            "expiresAt": "2025-01-01T01:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let strategy = try decoder.decode(DownloadStrategy.self, from: data)

        XCTAssertEqual(strategy.method, "presigned")
        XCTAssertNotNil(strategy.url)
        XCTAssertNotNil(strategy.expiresAt)
    }

    func testListResponseDecoding() throws {
        let json = """
        {
            "data": [
                {
                    "bucket": "avatars",
                    "key": "file1.jpg",
                    "size": 1000,
                    "mimeType": "image/jpeg",
                    "uploadedAt": "2025-01-01T00:00:00Z",
                    "url": "https://storage.insforge.com/avatars/file1.jpg"
                }
            ],
            "pagination": {
                "offset": 0,
                "limit": 100,
                "total": 1
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(ListResponse.self, from: data)

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.key, "file1.jpg")
        XCTAssertEqual(response.pagination?.total, 1)
    }

    /// Test listing buckets
    func testListBuckets() async throws {
        print("🔵 Testing listBuckets...")

        let buckets = try await insForgeClient.storage.listBuckets()

        XCTAssertNotNil(buckets)
        print("✅ Found \(buckets.count) bucket(s)")
        for bucket in buckets {
            print("   - \(bucket)")
        }
    }

    /// Test creating a bucket
    func testCreateBucket() async throws {
        print("🔵 Testing createBucket...")

        // Delete if already exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)

        // Create bucket with options
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Verify it exists
        let buckets = try await insForgeClient.storage.listBuckets()
        XCTAssertTrue(buckets.contains(testBucketName),
                     "Created bucket should appear in bucket list")

        print("✅ Successfully created bucket: \(testBucketName)")
    }

    /// Test updating a bucket
    func testUpdateBucket() async throws {
        print("🔵 Testing updateBucket...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Update bucket to private
        try await insForgeClient.storage.updateBucket(
            testBucketName,
            options: BucketOptions(isPublic: false)
        )

        print("✅ Successfully updated bucket: \(testBucketName)")
    }

    /// Test uploading a file with specific path
    func testUploadFile() async throws {
        print("🔵 Testing upload with path...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Create test file
        let testContent = "Hello from Swift SDK".data(using: .utf8)!
        let filePath = "test-files/hello-\(UUID().uuidString).txt"

        // Upload file
        let fileApi = await insForgeClient.storage.from(testBucketName)
        let uploadedFile = try await fileApi.upload(
            path: filePath,
            data: testContent,
            options: FileOptions(contentType: "text/plain")
        )

        // Verify
        XCTAssertEqual(uploadedFile.key, filePath)
        XCTAssertEqual(uploadedFile.bucket, testBucketName)

        print("✅ Uploaded file: \(uploadedFile.key)")
    }

    /// Test uploading a file with specific path
    func testUploadLocalImageFile() async throws {
        print("🔵 Testing upload with path...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Load test image from file (relative to Tests directory)
        let imagePath = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("cpu.png").path
        let imageURL = URL(fileURLWithPath: imagePath)
        let testContent = try Data(contentsOf: imageURL)
        let filePath = "test-files/hello-\(UUID().uuidString).png"

        // Upload file
        let fileApi = await insForgeClient.storage.from(testBucketName)
        let uploadedFile = try await fileApi.upload(
            path: filePath,
            data: testContent,
            options: FileOptions(contentType: "image/png")
        )

        // Verify
        XCTAssertEqual(uploadedFile.key, filePath)
        XCTAssertEqual(uploadedFile.bucket, testBucketName)

        print("✅ Uploaded file: \(uploadedFile.key)")
        // List files
        let files = try await fileApi.list()
        print("✅ Listed \(files.count) file(s) in bucket after upload")
        for file in files.prefix(5) {
            print("   - \(file.key)")
        }
        let foundFile = files.first { $0.key == uploadedFile.key }
        XCTAssertNotNil(foundFile, "Uploaded file should be present in the file list")
    }

    /// Test uploading a file with auto-generated key
    func testUploadFileAutoKey() async throws {
        print("🔵 Testing upload with auto-generated key...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Create test file
        let testContent = "Hello from Swift SDK - Auto Key".data(using: .utf8)!

        // Upload file with auto-generated key
        let fileApi = await insForgeClient.storage.from(testBucketName)
        let uploadedFile = try await fileApi.upload(
            data: testContent,
            fileName: "auto-test.txt",
            options: FileOptions(contentType: "text/plain")
        )

        // Verify
        XCTAssertFalse(uploadedFile.key.isEmpty)
        XCTAssertEqual(uploadedFile.bucket, testBucketName)

        print("✅ Uploaded file with auto key: \(uploadedFile.key)")
    }

    /// Test uploading from file URL
    func testUploadFileFromURL() async throws {
        print("🔵 Testing upload from file URL...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-upload-\(UUID().uuidString).txt")
        let testContent = "Hello from file URL upload"
        try testContent.write(to: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        // Upload from file URL
        let filePath = "url-upload-test.txt"
        let fileApi = await insForgeClient.storage.from(testBucketName)
        let uploadedFile = try await fileApi.upload(
            path: filePath,
            fileURL: tempFile,
            options: FileOptions(contentType: "text/plain")
        )

        // Verify
        XCTAssertEqual(uploadedFile.key, filePath)

        print("✅ Uploaded file from URL: \(uploadedFile.key)")
    }

    /// Test listing files in bucket
    func testListFiles() async throws {
        print("🔵 Testing list...")

        // Ensure bucket exists and has files
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload a test file first
        let testContent = "Test content for listing".data(using: .utf8)!
        _ = try await fileApi.upload(
            path: "test-list-\(UUID().uuidString).txt",
            data: testContent
        )

        // List files
        let files = try await fileApi.list()

        XCTAssertNotNil(files)
        XCTAssertFalse(files.isEmpty, "Bucket should contain at least one file")

        print("✅ Listed \(files.count) file(s) in bucket")
        for file in files.prefix(5) {
            print("   - \(file.key)")
        }
    }

    /// Test listing files with prefix
    func testListFilesWithPrefix() async throws {
        print("🔵 Testing list with prefix...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload files with specific prefix
        let prefix = "test-prefix-\(UUID().uuidString)"
        let testContent = "Test content".data(using: .utf8)!

        _ = try await fileApi.upload(path: "\(prefix)/file1.txt", data: testContent)
        _ = try await fileApi.upload(path: "\(prefix)/file2.txt", data: testContent)

        // List with prefix
        let files = try await fileApi.list(prefix: prefix, limit: 10)

        XCTAssertEqual(files.count, 2, "Should find exactly 2 files with the prefix")

        print("✅ Found \(files.count) file(s) with prefix '\(prefix)'")
    }

    /// Test listing files with options
    func testListFilesWithOptions() async throws {
        print("🔵 Testing list with options...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload multiple files
        let testContent = "Test content".data(using: .utf8)!
        for index in 0..<5 {
            _ = try await fileApi.upload(path: "paginated/file\(index).txt", data: testContent)
        }

        // List with pagination options
        let options = ListOptions(prefix: "paginated", limit: 2, offset: 0)
        let files = try await fileApi.list(options: options)

        XCTAssertEqual(files.count, 2, "Should return only 2 files due to limit")

        print("✅ Listed \(files.count) file(s) with pagination")
    }

    /// Test downloading a file
    func testDownloadFile() async throws {
        print("🔵 Testing download...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload a file first
        let originalContent = "Hello from Swift SDK - Download Test".data(using: .utf8)!
        let filePath = "test-download-\(UUID().uuidString).txt"

        _ = try await fileApi.upload(path: filePath, data: originalContent)

        // Download the file
        let downloadedData = try await fileApi.download(path: filePath)

        // Verify content matches
        XCTAssertEqual(downloadedData, originalContent)

        let downloadedString = String(data: downloadedData, encoding: .utf8)
        print("✅ Downloaded file: \(filePath)")
        print("   Content: \(downloadedString ?? "unable to decode")")
    }

    /// Test getting public URL
    func testGetPublicURL() async {
        print("🔵 Testing getPublicURL...")

        let fileApi = await insForgeClient.storage.from(testBucketName)
        let filePath = "test-files/public-test.jpg"

        let publicURL = fileApi.getPublicURL(path: filePath)

        XCTAssertTrue(publicURL.absoluteString.contains(testBucketName))
        XCTAssertTrue(publicURL.absoluteString.contains(filePath))

        print("✅ Generated public URL: \(publicURL.absoluteString)")
    }

    /// Test deleting a file
    func testDeleteFile() async throws {
        print("🔵 Testing delete...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload a file first
        let testContent = "To be deleted".data(using: .utf8)!
        let filePath = "test-delete-\(UUID().uuidString).txt"

        _ = try await fileApi.upload(path: filePath, data: testContent)

        // Delete the file
        try await fileApi.delete(path: filePath)

        // Verify it's gone by trying to download (should fail)
        do {
            _ = try await fileApi.download(path: filePath)
            XCTFail("Download should fail after deletion")
        } catch {
            // Expected to fail
            print("✅ Successfully deleted file: \(filePath)")
        }
    }

    /// Test getting upload strategy
    func testGetUploadStrategy() async throws {
        print("🔵 Testing getUploadStrategy...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Get upload strategy
        let strategy = try await fileApi.getUploadStrategy(
            filename: "test-strategy.jpg",
            contentType: "image/jpeg",
            size: 1024
        )

        XCTAssertFalse(strategy.method.isEmpty)
        XCTAssertFalse(strategy.uploadUrl.isEmpty)
        XCTAssertFalse(strategy.key.isEmpty)

        print("✅ Got upload strategy:")
        print("   Method: \(strategy.method)")
        print("   Key: \(strategy.key)")
        print("   Confirm required: \(strategy.confirmRequired)")
    }

    /// Test getting download strategy
    func testGetDownloadStrategy() async throws {
        print("🔵 Testing getDownloadStrategy...")

        // Ensure bucket exists
        try? await insForgeClient.storage.deleteBucket(testBucketName)
        try await insForgeClient.storage.createBucket(
            testBucketName,
            options: BucketOptions(isPublic: true)
        )

        let fileApi = await insForgeClient.storage.from(testBucketName)

        // Upload a file first
        let testContent = "Download strategy test".data(using: .utf8)!
        let filePath = "strategy-test.txt"
        _ = try await fileApi.upload(path: filePath, data: testContent)

        // Get download strategy
        let strategy = try await fileApi.getDownloadStrategy(
            path: filePath,
            expiresIn: 3600
        )

        XCTAssertFalse(strategy.method.isEmpty)
        XCTAssertFalse(strategy.url.isEmpty)

        print("✅ Got download strategy:")
        print("   Method: \(strategy.method)")
        print("   URL: \(strategy.url)")
    }

    /// Test deleting a bucket
    func testDeleteBucket() async throws {
        print("🔵 Testing deleteBucket...")

        // Create a temporary bucket
        let tempBucket = "temp-bucket-\(UUID().uuidString)"
        try await insForgeClient.storage.createBucket(
            tempBucket,
            options: BucketOptions(isPublic: true)
        )

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

    /// Test complete workflow: create bucket -> upload -> list -> download -> delete file -> delete bucket
    func testCompleteWorkflow() async throws {
        print("🔵 Testing complete storage workflow...")

        let workflowBucket = "workflow-test-\(UUID().uuidString)"

        // 1. Create bucket
        try await insForgeClient.storage.createBucket(
            workflowBucket,
            options: BucketOptions(isPublic: true)
        )
        print("   ✓ Created bucket")

        let fileApi = await insForgeClient.storage.from(workflowBucket)

        // 2. Upload file
        let content = "Workflow test content".data(using: .utf8)!
        let filePath = "workflow-test.txt"
        let uploaded = try await fileApi.upload(path: filePath, data: content)
        print("   ✓ Uploaded file: \(uploaded.key)")

        // 3. List files
        let files = try await fileApi.list()
        XCTAssertEqual(files.count, 1)
        print("   ✓ Listed files: \(files.count)")

        // 4. Download file
        let downloaded = try await fileApi.download(path: filePath)
        XCTAssertEqual(downloaded, content)
        print("   ✓ Downloaded and verified content")

        // 5. Delete file
        try await fileApi.delete(path: filePath)
        print("   ✓ Deleted file")

        // 6. Verify file is gone
        let filesAfterDelete = try await fileApi.list()
        XCTAssertEqual(filesAfterDelete.count, 0)
        print("   ✓ Verified file deletion")

        // 7. Delete bucket
        try await insForgeClient.storage.deleteBucket(workflowBucket)
        print("   ✓ Deleted bucket")

        print("✅ Complete workflow successful!")
    }
}
