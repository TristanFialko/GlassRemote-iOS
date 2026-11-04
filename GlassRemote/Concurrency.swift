import Foundation

/// Runs `operation` but stops waiting after `seconds`. A hung operation is abandoned rather
/// than awaited, so one dead socket cannot freeze connect, disconnect or recovery.
func withDeadline<T>(_ seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = DeadlineGate<T>(continuation)
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            gate.finish(nil)
        }
        Task {
            let value = await operation()
            timer.cancel()
            gate.finish(value)
        }
    }
}

private final class DeadlineGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Serial async queue: operations run one after another in the order they were enqueued.
final class TaskQueue {
    private var tail: Task<Void, Never> = Task {}

    func enqueue(_ operation: @escaping () async -> Void) {
        let previous = tail
        tail = Task {
            await previous.value
            await operation()
        }
    }
}
