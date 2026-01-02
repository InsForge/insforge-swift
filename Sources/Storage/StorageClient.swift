import Foundation
import InsForgeCore

// MARK: - Options

/// Options for file upload operations
public struct FileOptions: Sendable {
    /// The `Content-Type` header value. If not specified, it will be inferred from the file.
    public var contentType: String?

    /// Optional extra headers for the request.
    public var headers: [String: String]?

    public init(
        contentType: String? = nil,
        headers: [String: String]? = nil
    ) {
        self.contentType = contentType
        self.headers = headers
    }
}

/// Options for bucket creation
public struct BucketOptions: Sendable {
    /// Whether the bucket is publicly accessible. Defaults to true.
    public var isPublic: Bool

    public init(isPublic: Bool = true) {
        self.isPublic = isPublic
    }
}

/// Options for listing files
public struct ListOptions: Sendable {
    /// Filter objects by key prefix
    public var prefix: String?

    /// Maximum number of results (1-1000, default 100)
    public var limit: Int

    /// Offset for pagination (default 0)
    public var offset: Int

    public init(
        prefix: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.prefix = prefix
        self.limit = limit
        self.offset = offset
    }
}

// MARK: - Models

/// Stored file model returned from storage operations
public struct StoredFile: Codable, Sendable {
    public let bucket: String
    public let key: String
    public let size: Int
    public let mimeType: String?
    public let uploadedAt: Date
    public let url: String

    enum CodingKeys: String, CodingKey {
        case bucket, key, size, mimeType, uploadedAt, url
    }
}

/// List response with pagination
public struct ListResponse: Codable, Sendable {
    public let data: [StoredFile]
    public let pagination: Pagination?

    public struct Pagination: Codable, Sendable {
        public let offset: Int
        public let limit: Int
        public let total: Int
    }
}

/// Upload strategy response
public struct UploadStrategy: Codable, Sendable {
    public let method: String  // "presigned" or "direct"
    public let uploadUrl: String
    public let fields: [String: String]?
    public let key: String
    public let confirmRequired: Bool
    public let confirmUrl: String?
    public let expiresAt: String?
}

/// Download strategy response
public struct DownloadStrategy: Codable, Sendable {
    public let method: String  // "presigned" or "direct"
    public let url: String
    public let expiresAt: String?
}

// MARK: - Storage Client

/// Storage client for managing buckets and files
public actor StorageClient {
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let logger: (any InsForgeLogger)?

    public init(
        url: URL,
        headers: [String: String],
        logger: (any InsForgeLogger)? = nil
    ) {
        self.url = url
        self.headers = headers
        self.httpClient = HTTPClient(logger: logger)
        self.logger = logger
    }

    /// Get a file API reference for a bucket
    /// - Parameter id: The bucket id to operate on
    /// - Returns: StorageFileApi object for file operations
    public func from(_ id: String) -> StorageFileApi {
        StorageFileApi(
            bucketId: id,
            url: url,
            headers: headers,
            httpClient: httpClient,
            logger: logger
        )
    }

    // MARK: - Bucket Operations

    /// Bucket info returned from listBuckets
    public struct BucketInfo: Codable, Sendable {
        public let name: String
        public let `public`: Bool
        public let createdAt: String
    }

    /// List all buckets
    /// - Returns: Array of bucket names
    public func listBuckets() async throws -> [String] {
        let endpoint = url.appendingPathComponent("buckets")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // API returns array of bucket objects: [{"name":"...", "public":true, "createdAt":"..."}]
        let buckets = try response.decode([BucketInfo].self)
        return buckets.map { $0.name }
    }

    /// List all buckets with full info
    /// - Returns: Array of BucketInfo objects
    public func listBucketsWithInfo() async throws -> [BucketInfo] {
        let endpoint = url.appendingPathComponent("buckets")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        return try response.decode([BucketInfo].self)
    }

    /// Creates a new Storage bucket.
    /// - Parameters:
    ///   - name: A unique identifier for the bucket you are creating (alphanumeric, underscore, hyphen only).
    ///   - options: Options for creating the bucket.
    public func createBucket(_ name: String, options: BucketOptions = BucketOptions()) async throws {
        let endpoint = url.appendingPathComponent("buckets")

        let body: [String: Any] = [
            "bucketName": name,
            "isPublic": options.isPublic
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        logger?.log("Bucket '\(name)' created")
    }

    /// Updates a Storage bucket's visibility.
    /// - Parameters:
    ///   - name: The bucket name to update.
    ///   - options: Options for updating the bucket.
    public func updateBucket(_ name: String, options: BucketOptions) async throws {
        let endpoint = url.appendingPathComponent("buckets/\(name)")

        let body: [String: Any] = [
            "isPublic": options.isPublic
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try await httpClient.execute(
            .patch,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        logger?.log("Bucket '\(name)' updated")
    }

    /// Deletes an existing bucket.
    /// - Parameter name: The bucket name to delete.
    public func deleteBucket(_ name: String) async throws {
        let endpoint = url.appendingPathComponent("buckets/\(name)")

        _ = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        logger?.log("Bucket '\(name)' deleted")
    }
}

// MARK: - Storage File API

/// Storage file operations for a specific bucket
public struct StorageFileApi: Sendable {
    private let bucketId: String
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let logger: (any InsForgeLogger)?

    init(
        bucketId: String,
        url: URL,
        headers: [String: String],
        httpClient: HTTPClient,
        logger: (any InsForgeLogger)?
    ) {
        self.bucketId = bucketId
        self.url = url
        self.headers = headers
        self.httpClient = httpClient
        self.logger = logger
    }

    // MARK: - Upload

    /// Uploads a file to the bucket with a specific key.
    /// - Parameters:
    ///   - path: The object key (can include forward slashes for pseudo-folders).
    ///   - data: The file data to upload.
    ///   - options: Upload options.
    /// - Returns: StoredFile with upload details.
    @discardableResult
    public func upload(
        path: String,
        data: Data,
        options: FileOptions = FileOptions()
    ) async throws -> StoredFile {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)

        // PUT method for upload with specific key
        let response = try await httpClient.upload(
            url: endpoint,
            method: .put,
            headers: headers,
            file: data,
            fileName: path,
            mimeType: options.contentType ?? inferContentType(from: path)
        )

        let storedFile = try response.decode(StoredFile.self)
        logger?.log("File uploaded to '\(path)'")
        return storedFile
    }

    /// Uploads a file from a local file URL.
    /// - Parameters:
    ///   - path: The object key.
    ///   - fileURL: The local file URL to upload.
    ///   - options: Upload options.
    /// - Returns: StoredFile with upload details.
    @discardableResult
    public func upload(
        path: String,
        fileURL: URL,
        options: FileOptions = FileOptions()
    ) async throws -> StoredFile {
        let data = try Data(contentsOf: fileURL)
        return try await upload(path: path, data: data, options: options)
    }

    /// Uploads a file with auto-generated key.
    /// - Parameters:
    ///   - data: The file data to upload.
    ///   - fileName: Original filename for generating the key.
    ///   - options: Upload options.
    /// - Returns: StoredFile with upload details.
    @discardableResult
    public func upload(
        data: Data,
        fileName: String,
        options: FileOptions = FileOptions()
    ) async throws -> StoredFile {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")

        // POST method for upload with auto-generated key
        let response = try await httpClient.upload(
            url: endpoint,
            method: .post,
            headers: headers,
            file: data,
            fileName: fileName,
            mimeType: options.contentType ?? inferContentType(from: fileName)
        )

        let storedFile = try response.decode(StoredFile.self)
        logger?.log("File uploaded with auto-generated key")
        return storedFile
    }

    // MARK: - Download

    /// Downloads a file from the bucket.
    /// - Parameter path: The object key to download.
    /// - Returns: The file data.
    public func download(path: String) async throws -> Data {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        return response.data
    }

    // MARK: - List

    /// Lists all files in the bucket.
    /// - Parameter options: List options including prefix, limit, and offset.
    /// - Returns: Array of StoredFile objects.
    public func list(options: ListOptions = ListOptions()) async throws -> [StoredFile] {
        var components = URLComponents(
            url: url
                .appendingPathComponent("buckets")
                .appendingPathComponent(bucketId)
                .appendingPathComponent("objects"),
            resolvingAgainstBaseURL: false
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(options.limit)"),
            URLQueryItem(name: "offset", value: "\(options.offset)")
        ]

        if let prefix = options.prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }

        components?.queryItems = queryItems

        guard let requestURL = components?.url else {
            throw InsForgeError.invalidURL
        }

        let response = try await httpClient.execute(
            .get,
            url: requestURL,
            headers: headers
        )

        let listResponse = try response.decode(ListResponse.self)
        return listResponse.data
    }

    /// Lists files with a specific prefix.
    /// - Parameters:
    ///   - prefix: Filter objects by key prefix.
    ///   - limit: Maximum number of results (default 100).
    ///   - offset: Offset for pagination (default 0).
    /// - Returns: Array of StoredFile objects.
    public func list(
        prefix: String,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [StoredFile] {
        try await list(options: ListOptions(prefix: prefix, limit: limit, offset: offset))
    }

    // MARK: - Delete

    /// Deletes a file from the bucket.
    /// - Parameter path: The object key to delete.
    public func delete(path: String) async throws {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)

        _ = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        logger?.log("File '\(path)' deleted from bucket '\(bucketId)'")
    }

    // MARK: - Public URL

    /// Gets the public URL for a file in a public bucket.
    /// - Parameter path: The object key.
    /// - Returns: The public URL for the file.
    public func getPublicURL(path: String) -> URL {
        url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)
    }

    // MARK: - Upload Strategy

    /// Gets the upload strategy for a file (direct or presigned URL).
    /// - Parameters:
    ///   - filename: Original filename for generating unique key.
    ///   - contentType: MIME type of the file.
    ///   - size: File size in bytes.
    /// - Returns: UploadStrategy with upload details.
    public func getUploadStrategy(
        filename: String,
        contentType: String? = nil,
        size: Int? = nil
    ) async throws -> UploadStrategy {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("upload-strategy")

        var body: [String: Any] = ["filename": filename]
        if let contentType = contentType {
            body["contentType"] = contentType
        }
        if let size = size {
            body["size"] = size
        }

        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        return try response.decode(UploadStrategy.self)
    }

    /// Confirms a presigned upload.
    /// - Parameters:
    ///   - path: The object key.
    ///   - size: File size in bytes.
    ///   - contentType: MIME type of the file.
    ///   - etag: S3 ETag of the uploaded object (optional).
    /// - Returns: StoredFile with confirmed upload details.
    @discardableResult
    public func confirmUpload(
        path: String,
        size: Int,
        contentType: String? = nil,
        etag: String? = nil
    ) async throws -> StoredFile {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)
            .appendingPathComponent("confirm-upload")

        var body: [String: Any] = ["size": size]
        if let contentType = contentType {
            body["contentType"] = contentType
        }
        if let etag = etag {
            body["etag"] = etag
        }

        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        return try response.decode(StoredFile.self)
    }

    // MARK: - Download Strategy

    /// Gets the download strategy for a file (direct or presigned URL).
    /// - Parameters:
    ///   - path: The object key.
    ///   - expiresIn: URL expiration time in seconds (default 3600).
    /// - Returns: DownloadStrategy with download details.
    public func getDownloadStrategy(
        path: String,
        expiresIn: Int = 3600
    ) async throws -> DownloadStrategy {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(bucketId)
            .appendingPathComponent("objects")
            .appendingPathComponent(path)
            .appendingPathComponent("download-strategy")

        let body: [String: Any] = ["expiresIn": expiresIn]
        let data = try JSONSerialization.data(withJSONObject: body)

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: data
        )

        return try response.decode(DownloadStrategy.self)
    }

    // MARK: - Private Helpers

    private func inferContentType(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "pdf":
            return "application/pdf"
        case "json":
            return "application/json"
        case "txt":
            return "text/plain"
        case "html":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "video/mp4"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}
