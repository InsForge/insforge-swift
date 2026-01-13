import Foundation
import InsForge
import InsForgeAuth
import InsForgeStorage
import Logging

/// Shared InsForge client instance
final class InsForgeService: @unchecked Sendable {
    static let shared = InsForgeService()

    let client: InsForgeClient

    private init() {
        let options = InsForgeClientOptions(
            global: .init(
                logLevel: .debug,
                logDestination: .osLog,
                logSubsystem: "com.example.TwitterClone"
            )
        )

        client = InsForgeClient(
            baseURL: URL(string: "http://localhost:7130")!,
            anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3OC0xMjM0LTU2NzgtOTBhYi1jZGVmMTIzNDU2NzgiLCJlbWFpbCI6ImFub25AaW5zZm9yZ2UuY29tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyODI5OTN9.qa445nSDPeFHycsHKZpog9IXoBi129N-uAE-wYKfY0Q",
            options: options
        )
    }
}

// Convenience accessor
var insforge: InsForgeClient {
    InsForgeService.shared.client
}
