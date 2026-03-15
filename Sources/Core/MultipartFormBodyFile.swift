import Foundation

struct MultipartFormBodyFile: Sendable {
    static let defaultChunkSize = 1_048_576

    let fileURL: URL
    let boundary: String
    let contentLength: UInt64

    static func create(
        formFields: [String: String],
        sourceFileURL: URL,
        fileName: String,
        mimeType: String,
        chunkSize: Int = defaultChunkSize
    ) throws -> MultipartFormBodyFile {
        guard chunkSize > 0 else {
            throw InsForgeError.validationError("Chunk size must be greater than 0")
        }

        let boundary = "InsForgeBoundary-\(UUID().uuidString)"
        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("insforge-multipart-\(UUID().uuidString)")

        guard FileManager.default.createFile(atPath: tempFileURL.path, contents: nil) else {
            throw InsForgeError.unknown("Failed to create temporary upload body file")
        }

        var shouldCleanupTemporaryFile = true
        defer {
            if shouldCleanupTemporaryFile {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }

        let outputHandle = try FileHandle(forWritingTo: tempFileURL)
        defer { try? outputHandle.close() }

        var contentLength: UInt64 = 0

        func write(_ data: Data) throws {
            try outputHandle.write(contentsOf: data)
            contentLength += UInt64(data.count)
        }

        for (key, value) in formFields {
            try write(Data("--\(boundary)\r\n".utf8))
            try write(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            try write(Data("\(value)\r\n".utf8))
        }

        try write(Data("--\(boundary)\r\n".utf8))
        try write(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        try write(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let inputHandle = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? inputHandle.close() }

        while true {
            let chunk = inputHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                break
            }
            try write(chunk)
        }

        try write(Data("\r\n--\(boundary)--\r\n".utf8))
        try outputHandle.synchronize()

        shouldCleanupTemporaryFile = false

        return MultipartFormBodyFile(
            fileURL: tempFileURL,
            boundary: boundary,
            contentLength: contentLength
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
