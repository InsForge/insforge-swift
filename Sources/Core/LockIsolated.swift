import Foundation

/// Thread-safe value wrapper using NSLock
/// Based on Supabase's LockIsolated pattern
public final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self._value = value
    }

    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    public func withValue<T>(_ operation: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation(&_value)
    }

    public func setValue(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}
