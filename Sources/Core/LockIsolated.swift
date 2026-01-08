import Foundation

/// Thread-safe value wrapper using NSLock.
///
/// Based on Supabase's LockIsolated pattern. Provides synchronized access
/// to a mutable value across concurrent contexts.
public final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    /// Creates a new lock-isolated value.
    /// - Parameter value: The initial value to wrap.
    public init(_ value: Value) {
        self._value = value
    }

    /// The current value, accessed in a thread-safe manner.
    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    /// Performs an operation on the value while holding the lock.
    /// - Parameter operation: A closure that receives an inout reference to the value.
    /// - Returns: The result of the operation.
    /// - Throws: Rethrows any error thrown by the operation.
    public func withValue<T>(_ operation: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation(&_value)
    }

    /// Sets a new value in a thread-safe manner.
    /// - Parameter newValue: The new value to set.
    public func setValue(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}
