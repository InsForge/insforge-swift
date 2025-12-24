import Foundation
import InsForgeCore

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

    /// Get a bucket reference
    public func bucket(_ name: String) -> StorageBucket {
        StorageBucket(
            name: name,
            url: url,
            headers: headers,
            httpClient: httpClient,
            logger: logger
        )
    }

    /// List all buckets
    public func listBuckets() async throws -> [String] {
        let endpoint = url.appendingPathComponent("buckets")

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        struct BucketInfo: Codable {
            let name: String
            let `public`: Bool
            let createdAt: String
        }

        // API returns array of bucket objects directly
        let bucketInfos = try response.decode([BucketInfo].self)
        return bucketInfos.map { $0.name }
    }

    /// Create a new bucket
    public func createBucket(
        name: String,
        isPublic: Bool = true
    ) async throws {
        let endpoint = url.appendingPathComponent("buckets")

        let body: [String: Any] = [
            "bucketName": name,
            "isPublic": isPublic
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

    /// Delete a bucket
    public func deleteBucket(_ name: String) async throws {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)

        _ = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        logger?.log("Bucket '\(name)' deleted")
    }
}

/// Storage bucket operations
public struct StorageBucket: Sendable {
    private let name: String
    private let url: URL
    private let headers: [String: String]
    private let httpClient: HTTPClient
    private let logger: (any InsForgeLogger)?

    init(
        name: String,
        url: URL,
        headers: [String: String],
        httpClient: HTTPClient,
        logger: (any InsForgeLogger)?
    ) {
        self.name = name
        self.url = url
        self.headers = headers
        self.httpClient = httpClient
        self.logger = logger
    }

    // MARK: - Upload

    /// Upload a file with auto-generated key
    public func upload(
        file: Data,
        fileName: String,
        mimeType: String
    ) async throws -> StoredFile {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)
            .appendingPathComponent("objects")

        let response = try await httpClient.upload(
            url: endpoint,
            headers: headers,
            file: file,
            fileName: fileName,
            mimeType: mimeType
        )

        return try response.decode(StoredFile.self)
    }

    /// Upload a file with specific key
    public func upload(
        file: Data,
        key: String,
        mimeType: String
    ) async throws -> StoredFile {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)
            .appendingPathComponent("objects")
            .appendingPathComponent(key)

        let response = try await httpClient.upload(
            url: endpoint,
            headers: headers,
            file: file,
            fileName: key,
            mimeType: mimeType
        )

        return try response.decode(StoredFile.self)
    }

    // MARK: - Download

    /// Download a file
    public func download(key: String) async throws -> Data {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)
            .appendingPathComponent("objects")
            .appendingPathComponent(key)

        let response = try await httpClient.execute(
            .get,
            url: endpoint,
            headers: headers
        )

        return response.data
    }

    /// Get public URL for a file
    public func getPublicURL(key: String) -> URL {
        url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)
            .appendingPathComponent("objects")
            .appendingPathComponent(key)
    }

    // MARK: - List

    /// List files in bucket
    public func list(
        prefix: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [StoredFile] {
        var components = URLComponents(
            url: url
                .appendingPathComponent("buckets")
                .appendingPathComponent(name)
                .appendingPathComponent("objects"),
            resolvingAgainstBaseURL: false
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        if let prefix = prefix {
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

        struct ListResponse: Codable {
            let data: [StoredFile]
        }

        let listResponse = try response.decode(ListResponse.self)
        return listResponse.data
    }

    // MARK: - Delete

    /// Delete a file
    public func delete(key: String) async throws {
        let endpoint = url
            .appendingPathComponent("buckets")
            .appendingPathComponent(name)
            .appendingPathComponent("objects")
            .appendingPathComponent(key)

        _ = try await httpClient.execute(
            .delete,
            url: endpoint,
            headers: headers
        )

        logger?.log("File '\(key)' deleted from bucket '\(name)'")
    }
}

/// Stored file model
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
