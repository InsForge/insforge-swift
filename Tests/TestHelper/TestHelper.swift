import Foundation
import InsForge

/// Shared test configuration and helper for all InsForge tests
///
/// This provides a centralized place to configure:
/// - InsForge instance URL
/// - API keys (anon and authenticated)
/// - Common test utilities
///
/// Usage:
/// ```swift
/// let client = TestHelper.createClient()
/// ```
public enum TestHelper {
    // MARK: - Configuration

    /// InsForge instance URL for testing
    public static let insForgeURL = "https://pg6afqz9.us-east.insforge.app"

    /// Anonymous API key for public operations
    /// JWT token split into parts to comply with line length limits
    public static let anonKey = [
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "eyJzdWIiOiIxMjM0NTY3OC0xMjM0LTU2NzgtOTBhYi1jZGVmMTIzNDU2NzgiLCJlbWFpbCI6ImFub25AaW5zZm9yZ2UuY29tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5MDc5MzJ9",
        "K0semVtcacV55qeEhVUI3WKWzT7p87JU7wNzdXysRWo"
    ].joined(separator: ".")

    /// Authenticated user token for testing (optional, may expire)
    public static let userToken = [
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "eyJzdWIiOiIwODVhNDgxZS05NGI4LTRiZjktYjNhMC03ZjBlNTBmN2EwNzIiLCJlbWFpbCI6Imp1bndlbi5mZW5nQGluc2ZvcmdlLmRldiIsInJvbGUiOiJhdXRoZW50aWNhdGVkIiwiaWF0IjoxNzY3NzQyMTE2LCJleHAiOjE3NjgzNDY5MTZ9",
        "jhfprod2CU1Bn2j92wG9_j0MdmbtycpRI0SHoqqDtcc"
    ].joined(separator: ".")

    // MARK: - Client Creation

    /// Create a new InsForge client with default test configuration
    public static func createClient() -> InsForgeClient {
        return InsForgeClient(
            baseURL: URL(string: insForgeURL)!,
            anonKey: anonKey
        )
    }

    /// Create a new InsForge client with custom options
    public static func createClient(options: InsForgeClientOptions) -> InsForgeClient {
        return InsForgeClient(
            baseURL: URL(string: insForgeURL)!,
            anonKey: anonKey,
            options: options
        )
    }

    /// Base URL as URL object
    public static var baseURL: URL {
        URL(string: insForgeURL)!
    }
}
