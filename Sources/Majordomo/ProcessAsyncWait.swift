import Foundation

private final class ExitResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Runs `block` at most once, regardless of how many call sites race to
    /// resume. Guarantees the checked continuation is never resumed twice.
    func resumeOnce(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        block()
    }
}

extension Process {
    /// Awaits process exit without blocking a thread.
    ///
    /// `waitUntilExit()` parks the calling thread until the process ends, which
    /// starves the Swift cooperative thread pool when called from an async
    /// context (and freezes the UI when called on the main thread). This uses
    /// the termination handler instead, so the awaiting task simply suspends.
    ///
    /// Handles the race where the process exits between installing the handler
    /// and the `isRunning` re-check: whichever path fires first resumes, the
    /// other is a no-op.
    func waitForExit() async -> Int32 {
        let guardian = ExitResumeGuard()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            terminationHandler = { process in
                process.terminationHandler = nil
                guardian.resumeOnce { continuation.resume(returning: process.terminationStatus) }
            }
            if !isRunning {
                let status = terminationStatus
                guardian.resumeOnce { continuation.resume(returning: status) }
            }
        }
    }
}
