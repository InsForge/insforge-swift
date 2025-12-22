import Foundation

/// Logger protocol for InsForge SDK
public protocol InsForgeLogger: Sendable {
    func log(_ message: String)
    func error(_ message: String)
}

/// Console logger implementation
public struct ConsoleLogger: InsForgeLogger {
    public init() {}

    public func log(_ message: String) {
        print("[InsForge] \(message)")
    }

    public func error(_ message: String) {
        print("[InsForge Error] \(message)")
    }
}

/// No-op logger
public struct NoOpLogger: InsForgeLogger {
    public init() {}

    public func log(_ message: String) {}
    public func error(_ message: String) {}
}
