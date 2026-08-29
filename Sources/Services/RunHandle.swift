import Foundation

/// Tracks the process backing one task's in-progress backup run, so the UI
/// can pause/resume (SIGSTOP/SIGCONT) or stop it independently of any other
/// task's run. Safe to call from any thread: the run loop attaches/detaches
/// the live process from its background thread while pause/stop come from
/// the main actor.
final class RunHandle {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var paused = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return paused
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldSuspend = paused
        lock.unlock()
        if shouldSuspend { process.suspend() }
    }

    func detach() {
        lock.lock(); defer { lock.unlock() }
        process = nil
    }

    /// Toggles pause state, applying it to the in-flight process if there is one.
    @discardableResult
    func togglePause() -> Bool {
        lock.lock()
        paused.toggle()
        let shouldPause = paused
        let currentProcess = process
        lock.unlock()
        if shouldPause {
            currentProcess?.suspend()
        } else {
            currentProcess?.resume()
        }
        return shouldPause
    }

    func cancel() {
        lock.lock()
        cancelled = true
        paused = false
        let currentProcess = process
        lock.unlock()
        // A suspended process won't act on SIGTERM until it's resumed.
        currentProcess?.resume()
        currentProcess?.terminate()
    }
}
