import XCTest
@testable import InsForgeStorage

/// Offline unit tests for client-side object key generation.
///
/// `upload(data:fileName:options:)` mints a unique, collision-free key
/// client-side (`<sanitized-base>-<timestamp>-<random><ext>`) and uploads
/// through the standard `upload(path:data:options:)` path. These tests run
/// without a backend and are part of the deterministic CI suite.
final class StorageObjectKeyTests: XCTestCase {
    /// Keys follow `<sanitized-base>-<timestamp>-<random><ext>` and preserve the extension
    func testGeneratedKeyPreservesExtensionAndBase() throws {
        let key = StorageFileApi.generateObjectKey(from: "report.pdf")

        let regex = try NSRegularExpression(pattern: "^report-\\d+-[a-z0-9]+\\.pdf$")
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(
            regex.firstMatch(in: key, range: range),
            "Key '\(key)' should match <base>-<timestamp>-<random>.pdf"
        )
    }

    /// Characters outside [a-zA-Z0-9-_] in the base are replaced with '-'
    func testGeneratedKeySanitizesSpecialCharacters() throws {
        let key = StorageFileApi.generateObjectKey(from: "my photo (1).png")

        XCTAssertTrue(key.hasSuffix(".png"))
        let regex = try NSRegularExpression(pattern: "^my-photo--1--\\d+-[a-z0-9]+\\.png$")
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(
            regex.firstMatch(in: key, range: range),
            "Key '\(key)' should sanitize non-alphanumeric characters to '-'"
        )
    }

    /// Long base names are truncated to 32 characters
    func testGeneratedKeyTruncatesLongBase() {
        let longBase = String(repeating: "a", count: 100)
        let key = StorageFileApi.generateObjectKey(from: "\(longBase).txt")

        XCTAssertTrue(key.hasPrefix(String(repeating: "a", count: 32) + "-"))
        XCTAssertFalse(key.hasPrefix(String(repeating: "a", count: 33)))
        XCTAssertTrue(key.hasSuffix(".txt"))
    }

    /// A filename without an extension gets no extension in the key
    func testGeneratedKeyWithoutExtension() throws {
        let key = StorageFileApi.generateObjectKey(from: "file")

        let regex = try NSRegularExpression(pattern: "^file-\\d+-[a-z0-9]+$")
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(
            regex.firstMatch(in: key, range: range),
            "Key '\(key)' should have no extension"
        )
    }

    /// A leading dot (dotfile) is treated as part of the base, not an extension
    func testGeneratedKeyTreatsDotfileAsBase() throws {
        let key = StorageFileApi.generateObjectKey(from: ".gitignore")

        let regex = try NSRegularExpression(pattern: "^-gitignore-\\d+-[a-z0-9]+$")
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(
            regex.firstMatch(in: key, range: range),
            "Key '\(key)' should treat a dotfile name as the base"
        )
    }

    /// An empty base falls back to 'file'
    func testGeneratedKeyFallsBackToFileForEmptyBase() throws {
        let key = StorageFileApi.generateObjectKey(from: "")

        let regex = try NSRegularExpression(pattern: "^file-\\d+-[a-z0-9]+$")
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(
            regex.firstMatch(in: key, range: range),
            "Key '\(key)' should fall back to a 'file' base"
        )
    }

    /// Repeated calls with the same filename produce distinct keys
    func testGeneratedKeysAreUnique() {
        let keys = (0..<50).map { _ in StorageFileApi.generateObjectKey(from: "avatar.jpg") }

        XCTAssertEqual(Set(keys).count, keys.count, "Generated keys must be collision-free")
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("avatar-") && $0.hasSuffix(".jpg") })
    }
}
