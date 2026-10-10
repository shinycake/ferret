import Foundation

/// Starts and stops the search daemon at launch and quit.
/// Process management is replaced when the core lane's actor lands; the menu already consumes `health`.
final class DaemonManager: @unchecked Sendable {
    let health: AsyncStream<ShellHealth>
    private let continuation: AsyncStream<ShellHealth>.Continuation
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    init() {
        var continuation: AsyncStream<ShellHealth>.Continuation!
        health = AsyncStream { continuation = $0 }
        self.continuation = continuation
        continuation.yield(.starting)
    }

    func start() async {
        lock.lock()
        let already = started
        started = true
        lock.unlock()
        guard !already else { return }
        logLine("ferret: DaemonManager.start")
        continuation.yield(.failed("Search engine not connected"))
    }

    func stop() {
        lock.lock()
        let already = stopped
        stopped = true
        lock.unlock()
        guard !already else { return }
        logLine("ferret: DaemonManager.stop")
        continuation.yield(.stopped)
        continuation.finish()
    }
}
