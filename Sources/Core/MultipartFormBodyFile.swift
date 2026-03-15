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

        let outputHandle = try FileHandle(forWritingTo: tempFileURL)
        defer { try? outputHandle.close() }

        for (key, value) in formFields {
            try outputHandle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try outputHandle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            try outputHandle.write(contentsOf: Data("\(value)\r\n".utf8))
        }

        try outputHandle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try outputHandle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        try outputHandle.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let inputHandle = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? inputHandle.close() }

        while true {
            let chunk = inputHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                break
            }
            try outputHandle.write(contentsOf: chunk)
        }

        try outputHandle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try outputHandle.synchronize()

        let attributes = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        let fileSize = attributes[.size] as? NSNumber

        return MultipartFormBodyFile(
            fileURL: tempFileURL,
            boundary: boundary,
            contentLength: fileSize?.uint64Value ?? 0
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
