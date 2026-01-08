import Foundation
import InsForgeCore
import Logging

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
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    public init(
        url: URL,
        headersProvider: LockIsolated<[String: String]>
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = HTTPClient()
    }

    /// Get a file API reference for a bucket
    /// - Parameter id: The bucket id to operate on
    /// - Returns: StorageFileApi object for file operations
    public func from(_ id: String) -> StorageFileApi {
        StorageFileApi(
            bucketId: id,
            url: url,
            headersProvider: headersProvider,
            httpClient: httpClient
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

        // Log request
        logger.debug("GET \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        // API returns array of bucket objects: [{"name":"...", "public":true, "createdAt":"..."}]
        let buckets = try response.decode([BucketInfo].self)
        logger.debug("Listed \(buckets.count) bucket(s)")
        return buckets.map { $0.name }
    }

    /// List all buckets with full info
    /// - Returns: Array of BucketInfo objects
    public func listBucketsWithInfo() async throws -> [BucketInfo] {
        let endpoint = url.appendingPathComponent("buckets")

        // Log request
        logger.debug("GET \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let buckets = try response.decode([BucketInfo].self)
        logger.debug("Listed \(buckets.count) bucket(s) with info")
        return buckets
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
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8), !responseString.isEmpty {
            logger.trace("Response body: \(responseString)")
        }

        logger.debug("Bucket '\(name)' created")
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
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("PATCH \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .patch,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8), !responseString.isEmpty {
            logger.trace("Response body: \(responseString)")
        }

        logger.debug("Bucket '\(name)' updated")
    }

    /// Deletes an existing bucket.
    /// - Parameter name: The bucket name to delete.
    public func deleteBucket(_ name: String) async throws {
        let endpoint = url.appendingPathComponent("buckets/\(name)")

        // Log request
        logger.debug("DELETE \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8), !responseString.isEmpty {
            logger.trace("Response body: \(responseString)")
        }

        logger.debug("Bucket '\(name)' deleted")
    }
}

// MARK: - Storage File API

/// Storage file operations for a specific bucket
public struct StorageFileApi: Sendable {
    private let bucketId: String
    private let url: URL
    private let headersProvider: LockIsolated<[String: String]>
    private let httpClient: HTTPClient
    private var logger: Logging.Logger { InsForgeLoggerFactory.shared }

    /// Get current headers (dynamically fetched to reflect auth state changes)
    private var headers: [String: String] {
        headersProvider.value
    }

    init(
        bucketId: String,
        url: URL,
        headersProvider: LockIsolated<[String: String]>,
        httpClient: HTTPClient
    ) {
        self.bucketId = bucketId
        self.url = url
        self.headersProvider = headersProvider
        self.httpClient = httpClient
    }

    // MARK: - Upload

    /// Uploads a file to the bucket with a specific key using presigned URL flow.
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
        let contentType = options.contentType ?? inferContentType(from: path)

        // 1. Get upload strategy
        let strategy = try await getUploadStrategy(
            filename: path,
            contentType: contentType,
            size: data.count
        )

        // 2. Upload to presigned URL or direct endpoint
        try await uploadToStrategy(strategy: strategy, data: data, contentType: contentType)

        // 3. Confirm upload if required
        if strategy.confirmRequired {
            let storedFile = try await confirmUpload(
                path: strategy.key,
                size: data.count,
                contentType: contentType
            )
            logger.debug("File uploaded to '\(path)' via presigned URL")
            return storedFile
        }

        // For direct uploads without confirmation, fetch the file info
        let files = try await list(options: ListOptions(prefix: strategy.key, limit: 1))
        guard let storedFile = files.first else {
            throw InsForgeError.httpError(statusCode: 404, message: "Uploaded file not found", error: nil, nextActions: nil)
        }
        logger.debug("File uploaded to '\(path)'")
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

    /// Uploads a file with auto-generated key using presigned URL flow.
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
        let contentType = options.contentType ?? inferContentType(from: fileName)

        // 1. Get upload strategy (auto-generates key)
        let strategy = try await getUploadStrategy(
            filename: fileName,
            contentType: contentType,
            size: data.count
        )

        // 2. Upload to presigned URL or direct endpoint
        try await uploadToStrategy(strategy: strategy, data: data, contentType: contentType)

        // 3. Confirm upload if required
        if strategy.confirmRequired {
            let storedFile = try await confirmUpload(
                path: strategy.key,
                size: data.count,
                contentType: contentType
            )
            logger.debug("File uploaded with auto-generated key via presigned URL")
            return storedFile
        }

        // For direct uploads without confirmation, fetch the file info
        let files = try await list(options: ListOptions(prefix: strategy.key, limit: 1))
        guard let storedFile = files.first else {
            throw InsForgeError.httpError(statusCode: 404, message: "Uploaded file not found", error: nil, nextActions: nil)
        }
        logger.debug("File uploaded with auto-generated key")
        return storedFile
    }

    /// Internal method to upload data to the strategy endpoint
    private func uploadToStrategy(strategy: UploadStrategy, data: Data, contentType: String) async throws {
        guard let uploadURL = URL(string: strategy.uploadUrl) else {
            throw InsForgeError.invalidURL
        }

        if strategy.method == "presigned", let fields = strategy.fields {
            // S3 presigned POST - include all fields from strategy
            try await uploadWithPresignedFields(url: uploadURL, fields: fields, data: data, contentType: contentType)
        } else {
            // Direct upload
            _ = try await httpClient.upload(
                url: uploadURL,
                method: .post,
                headers: headers,
                file: data,
                fileName: strategy.key,
                mimeType: contentType
            )
        }
    }

    /// Upload to S3 using presigned POST with form fields
    private func uploadWithPresignedFields(url: URL, fields: [String: String], data: Data, contentType: String) async throws {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add all presigned fields first (order matters, key must come before file)
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Add file field LAST (required for S3 presigned POST)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"file\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logger.debug("[UPLOAD-PRESIGNED] \(url)")

        let session = URLSession.shared
        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsForgeError.invalidResponse
        }

        logger.debug("Presigned upload response status: \(httpResponse.statusCode)")

        // S3 returns 204 No Content on successful POST upload
        if !(200..<300).contains(httpResponse.statusCode) {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Presigned upload failed"
            throw InsForgeError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorMessage,
                error: nil,
                nextActions: nil
            )
        }
    }

    // MARK: - Download

    /// Downloads a file from the bucket using presigned URL flow.
    /// - Parameter path: The object key to download.
    /// - Returns: The file data.
    public func download(path: String) async throws -> Data {
        // 1. Get download strategy
        let strategy = try await getDownloadStrategy(path: path)

        // 2. Download from the strategy URL (presigned or direct)
        guard let downloadURL = URL(string: strategy.url) else {
            throw InsForgeError.invalidURL
        }

        logger.debug("[DOWNLOAD] \(downloadURL)")

        let session = URLSession.shared
        let (data, response) = try await session.data(from: downloadURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsForgeError.invalidResponse
        }

        logger.debug("Download response status: \(httpResponse.statusCode)")

        if !(200..<300).contains(httpResponse.statusCode) {
            throw InsForgeError.httpError(
                statusCode: httpResponse.statusCode,
                message: "Download failed",
                error: nil,
                nextActions: nil
            )
        }

        return data
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

        // Log request
        logger.debug("GET \(requestURL.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .get,
            url: requestURL,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let listResponse = try response.decode(ListResponse.self)
        logger.debug("Listed \(listResponse.data.count) file(s) in bucket '\(bucketId)'")
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

        // Log request
        logger.debug("DELETE \(endpoint.absoluteString)")
        logger.trace("Request headers: \(headers.filter { $0.key != "Authorization" })")

        let response = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8), !responseString.isEmpty {
            logger.trace("Response body: \(responseString)")
        }

        logger.debug("File '\(path)' deleted from bucket '\(bucketId)'")
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
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let strategy = try response.decode(UploadStrategy.self)
        logger.debug("Got upload strategy: \(strategy.method) for '\(filename)'")
        return strategy
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
        // URL encode the path to handle slashes in the key
        // Using custom encoding to ensure / becomes %2F but doesn't get double-encoded
        let allowedChars = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? path
        let urlString = "\(url.absoluteString)/buckets/\(bucketId)/objects/\(encodedPath)/confirm-upload"
        guard let endpoint = URL(string: urlString) else {
            throw InsForgeError.invalidURL
        }

        var body: [String: Any] = ["size": size]
        if let contentType = contentType {
            body["contentType"] = contentType
        }
        if let etag = etag {
            body["etag"] = etag
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let storedFile = try response.decode(StoredFile.self)
        logger.debug("Upload confirmed for '\(path)'")
        return storedFile
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
        let requestHeaders = headers.merging(["Content-Type": "application/json"]) { $1 }

        // Log request
        logger.debug("POST \(endpoint.absoluteString)")
        logger.trace("Request headers: \(requestHeaders.filter { $0.key != "Authorization" })")
        if let bodyString = String(data: data, encoding: .utf8) {
            logger.trace("Request body: \(bodyString)")
        }

        let response = try await httpClient.execute(
            .post,
            url: endpoint,
            headers: requestHeaders,
            body: data
        )

        // Log response
        let statusCode = response.response.statusCode
        logger.debug("Response: \(statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            logger.trace("Response body: \(responseString)")
        }

        let strategy = try response.decode(DownloadStrategy.self)
        logger.debug("Got download strategy: \(strategy.method) for '\(path)'")
        return strategy
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
