import Foundation

/// 计数信号量，供批量操作 TaskGroup 限流（MRD 12：批量并发默认 4，可调 1–8）。
public final class AsyncSemaphore: Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var permits: Int
        var waiters: [CheckedContinuation<Void, Never>] = []
        init(permits: Int) { self.permits = permits }
    }

    private let state: State

    public init(_ permits: Int) {
        state = State(permits: max(1, permits))
    }

    public func wait() async {
        let fastPath = state.lock.withLock { () -> Bool in
            guard state.permits > 0 else { return false }
            state.permits -= 1
            return true
        }
        if fastPath { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let shouldResume = state.lock.withLock { () -> Bool in
                if state.permits > 0 {
                    state.permits -= 1
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    public func signal() {
        let waiter: CheckedContinuation<Void, Never>? = state.lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if !state.waiters.isEmpty {
                return state.waiters.removeFirst()
            }
            state.permits += 1
            return nil
        }
        waiter?.resume()
    }

    public func withPermit<T>(_ body: () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await body()
    }
}
