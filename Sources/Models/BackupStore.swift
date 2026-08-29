import Foundation
import Combine
import SwiftUI // for Array.move(fromOffsets:toOffset:), used by moveTasks

@MainActor
final class BackupStore: ObservableObject {

    enum RunStatus: Equatable {
        case idle
        case running
        case succeeded(Date)
        case failed(Date)
        case stopped(Date)
    }

    @Published private(set) var tasks: [SyncTask] = []
    @Published private(set) var runStatuses: [UUID: RunStatus] = [:]
    @Published private(set) var pausedTaskIDs: Set<UUID> = []
    /// Set the moment Pause/Stop is clicked, cleared once it actually takes
    /// effect — lets the UI show "Pausing…"/"Stopping…" for any gap between
    /// the click and the real state change (e.g. rsync taking a moment to exit).
    @Published private(set) var pausingTaskIDs: Set<UUID> = []
    @Published private(set) var stoppingTaskIDs: Set<UUID> = []
    /// The rsync warning/error lines (permission denied, vanished files, …)
    /// that explain why a task's last run failed — cleared on a fresh run or
    /// once it succeeds. Lets the UI show a reason without the raw log.
    @Published private(set) var taskFailureReasons: [UUID: [String]] = [:]
    /// A summary of the most recently finished run (cleared once a fresh run
    /// starts, or when the user dismisses it) — drives the completion banner.
    @Published private(set) var lastRunSummaries: [UUID: RunSummary] = [:]
    @Published private(set) var logText: String = "(no log yet)"

    struct RunSummary: Equatable {
        enum Outcome: Equatable { case succeeded, failed, stopped }
        let outcome: Outcome
        let date: Date
        let duration: TimeInterval
        let bytesTransferred: Int64
    }
    @Published var lastError: String?
    @Published var fullDiskAccessWarning: String?
    @Published var availableUpdate: UpdateChecker.ReleaseInfo?
    @Published var manualUpdateCheckResult: ManualUpdateCheckResult?

    enum ManualUpdateCheckResult: Identifiable {
        case upToDate
        case failed(String)
        var id: String {
            switch self {
            case .upToDate: return "upToDate"
            case .failed(let message): return "failed-\(message)"
            }
        }
    }

    /// Deliberately not @Published — see SyncProgressTracker's doc comment.
    let progressTracker = SyncProgressTracker()

    private var runHandles: [UUID: RunHandle] = [:]

    /// Drives the animated app icon (main window background + menu bar icon)
    /// so both share one rotation clock tied to actual sync activity.
    let iconRotation = SquaresRotation(secondsPerRevolution: 5)

    init() {
        ConfigIO.ensureConfigFilesExist()
        tasks = ConfigIO.loadTasks()
        for task in tasks {
            runStatuses[task.id] = .idle
        }
        // A task can be left unnamed if the app quit before its name field
        // ever lost focus (e.g. right after creating it) — catch those here too.
        for task in tasks where task.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assignDefaultNameIfEmpty(task.id)
        }
        refreshLog()

        ScheduledRunBridge.observeIncomingRuns { [weak self] taskID in
            guard let self else { return }
            if let task = self.tasks.first(where: { $0.id == taskID }), case .once = task.schedule {
                self.clearSchedule(for: taskID)
            }
            self.runTaskNow(taskID)
        }
    }

    // MARK: - Permissions

    /// Called from ContentView's onAppear, not init(): if `fullDiskAccessWarning`
    /// becomes non-nil before the view (and its `.alert` modifier) has actually
    /// appeared, SwiftUI can fail to present the alert at all — a "born true"
    /// state with no attached view to react to the transition. Full Disk Access
    /// is all-or-nothing, but macOS can additionally gate individual removable/
    /// network volumes, so every currently mounted volume is probed too. Runs
    /// off the main thread — a stale network mount could otherwise stall this
    /// on the directory read (the volume probe itself is timeout-guarded too).
    func checkFullDiskAccess() {
        Task.detached(priority: .utility) { [weak self] in
            let hasFDA = FullDiskAccessChecker.hasFullDiskAccess
            let unreadableVolumes = FullDiskAccessChecker.unreadableMountedVolumeNames()
            var problems: [String] = []
            if !hasFDA {
                problems.append("Full Disk Access is not granted.")
            }
            if !unreadableVolumes.isEmpty {
                problems.append("Can't read: \(unreadableVolumes.joined(separator: ", ")).")
            }
            let warning = problems.isEmpty ? nil : problems.joined(separator: "\n")
            await MainActor.run {
                self?.fullDiskAccessWarning = warning
            }
        }
    }

    // MARK: - Updates

    private static let lastAutomaticUpdateCheckKey = "lastAutomaticUpdateCheckDate"

    /// Called on launch. Checks at most once a day, and only surfaces
    /// anything (via `availableUpdate`) when a newer release actually exists —
    /// silent otherwise, so it doesn't nag on every launch.
    func checkForUpdatesIfDue() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.lastAutomaticUpdateCheckKey) as? Date,
           Date().timeIntervalSince(last) < 86400 {
            return
        }
        defaults.set(Date(), forKey: Self.lastAutomaticUpdateCheckKey)
        checkForUpdates(manual: false)
    }

    /// `manual: true` (the menu bar "Check for Updates…" item) always reports
    /// a result, including "you're up to date" or a network failure; the
    /// automatic daily check only ever surfaces an actual available update.
    func checkForUpdates(manual: Bool) {
        Task {
            do {
                guard let release = try await UpdateChecker.fetchLatestRelease() else {
                    if manual { manualUpdateCheckResult = .upToDate }
                    return
                }
                if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentAppVersion) {
                    availableUpdate = release
                } else if manual {
                    manualUpdateCheckResult = .upToDate
                }
            } catch {
                if manual { manualUpdateCheckResult = .failed(error.localizedDescription) }
            }
        }
    }

    func runStatus(for taskID: UUID) -> RunStatus {
        runStatuses[taskID] ?? .idle
    }

    var overallStatus: RunStatus {
        let statuses = runStatuses.values
        if statuses.contains(.running) { return .running }
        let failedDates = statuses.compactMap { status -> Date? in
            if case .failed(let date) = status { return date }
            return nil
        }
        if let latestFailure = failedDates.max() { return .failed(latestFailure) }
        let stoppedDates = statuses.compactMap { status -> Date? in
            if case .stopped(let date) = status { return date }
            return nil
        }
        if let latestStop = stoppedDates.max() { return .stopped(latestStop) }
        let succeededDates = statuses.compactMap { status -> Date? in
            if case .succeeded(let date) = status { return date }
            return nil
        }
        if let latestSuccess = succeededDates.max() { return .succeeded(latestSuccess) }
        return .idle
    }

    var canRunAnyTask: Bool {
        tasks.contains { canRunTask($0.id) }
    }

    var isAnyTaskRunning: Bool {
        runStatuses.values.contains(.running)
    }

    var isAnyTaskPaused: Bool {
        !pausedTaskIDs.isEmpty
    }

    func isTaskPaused(_ taskID: UUID) -> Bool {
        pausedTaskIDs.contains(taskID)
    }

    func isTaskPausing(_ taskID: UUID) -> Bool {
        pausingTaskIDs.contains(taskID)
    }

    func isTaskStopping(_ taskID: UUID) -> Bool {
        stoppingTaskIDs.contains(taskID)
    }

    private func persist() {
        ConfigIO.saveTasks(tasks)
    }

    // MARK: - Tasks

    /// Set right after `addTask()`, so the new task's detail view knows to
    /// focus its name field immediately — the task starts unnamed, ready to type.
    @Published var pendingRenameTaskID: UUID?

    @discardableResult
    func addTask() -> UUID {
        let task = SyncTask(name: "")
        tasks.append(task)
        runStatuses[task.id] = .idle
        pendingRenameTaskID = task.id
        persist()
        return task.id
    }

    func removeTask(_ taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
        runStatuses[taskID] = nil
        try? LaunchAgentManager.remove(taskID: taskID)
        persist()
    }

    func renameTask(_ taskID: UUID, to name: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].name = name
        persist()
    }

    /// Called when the name field loses focus: an empty name (never typed
    /// into, or cleared back out) falls back to "Backup Task", "Backup Task 1", …
    func assignDefaultNameIfEmpty(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard tasks[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let taken = Set(tasks.filter { $0.id != taskID }.map(\.name))
        var candidate = "Backup Task"
        var suffix = 1
        while taken.contains(candidate) {
            candidate = "Backup Task \(suffix)"
            suffix += 1
        }
        tasks[index].name = candidate
        persist()
    }

    func moveTasks(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        tasks.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    // MARK: - Sources

    func addSource(_ path: String, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var resolved = path
        if resolved.hasSuffix("/") { resolved.removeLast() }
        guard !resolved.isEmpty, !tasks[index].sources.contains(where: { $0.path == resolved }) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else { return }
        tasks[index].sources.append(SourceEntry(path: resolved))
        persist()
    }

    func replaceSourcePath(_ sourceID: UUID, in taskID: UUID, with path: String) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let sourceIndex = tasks[taskIndex].sources.firstIndex(where: { $0.id == sourceID })
        else { return }
        var resolved = path
        if resolved.hasSuffix("/") { resolved.removeLast() }
        guard !resolved.isEmpty else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else { return }
        tasks[taskIndex].sources[sourceIndex].path = resolved
        persist()
    }

    func removeSources(at offsets: IndexSet, from taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].sources.remove(atOffsets: offsets)
        persist()
    }

    func setCopyMode(_ mode: CopyMode, forSource sourceID: UUID, in taskID: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let sourceIndex = tasks[taskIndex].sources.firstIndex(where: { $0.id == sourceID })
        else { return }
        tasks[taskIndex].sources[sourceIndex].copyMode = mode
        persist()
    }

    // MARK: - Destination

    func setDestination(_ path: String, for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var resolved = path
        if resolved.hasSuffix("/") { resolved.removeLast() }
        guard !resolved.isEmpty else { return }
        tasks[index].destination = resolved
        persist()
    }

    func isDestinationReachable(_ taskID: UUID) -> Bool {
        guard let destination = tasks.first(where: { $0.id == taskID })?.destination else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: destination, isDirectory: &isDir) && isDir.boolValue
    }

    func canRunTask(_ taskID: UUID) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return false }
        return !task.sources.isEmpty && isDestinationReachable(taskID) && runStatus(for: taskID) != .running
    }

    // MARK: - Schedule

    func applySchedule(_ kind: ScheduleKind, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        do {
            try LaunchAgentManager.install(taskID: taskID, schedule: kind)
            tasks[index].schedule = kind
            persist()
            lastError = nil
        } catch {
            lastError = "Could not install schedule: \(error.localizedDescription)"
        }
    }

    func clearSchedule(for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        do {
            try LaunchAgentManager.remove(taskID: taskID)
            tasks[index].schedule = .off
            persist()
            lastError = nil
        } catch {
            lastError = "Could not remove schedule: \(error.localizedDescription)"
        }
    }

    // MARK: - Log

    func refreshLog() {
        logText = ConfigIO.readRecentLogLines()
    }

    func clearLog() {
        ConfigIO.clearLog()
        refreshLog()
    }

    // MARK: - Run

    func runTaskNow(_ taskID: UUID) {
        guard canRunTask(taskID), let task = tasks.first(where: { $0.id == taskID }) else { return }
        let handle = RunHandle()
        runHandles[taskID] = handle
        pausedTaskIDs.remove(taskID)
        pausingTaskIDs.remove(taskID)
        stoppingTaskIDs.remove(taskID)
        progressTracker.clear(taskID)
        taskFailureReasons[taskID] = nil
        lastRunSummaries[taskID] = nil
        runStatuses[taskID] = .running
        syncIconRotationToActivity()
        let warningCollector = RsyncRunner.WarningCollector()
        let startDate = Date()
        Task.detached(priority: .userInitiated) {
            let ok = HeadlessRunner.run(task: task, handle: handle, onProgress: { progress in
                Task { @MainActor in
                    self.progressTracker.set(progress, for: taskID)
                }
            }, warningCollector: warningCollector)
            await self.finishRun(taskID: taskID, ok: ok, handle: handle, warnings: warningCollector.warnings, startDate: startDate)
        }
    }

    func dismissRunSummary(_ taskID: UUID) {
        lastRunSummaries[taskID] = nil
    }

    func runAllTasksNow() {
        for task in tasks where canRunTask(task.id) {
            runTaskNow(task.id)
        }
    }

    /// Pauses (SIGSTOP) or resumes (SIGCONT) one task's in-flight rsync process,
    /// independently of any other task's run.
    func togglePauseTask(_ taskID: UUID) {
        guard runStatus(for: taskID) == .running, let handle = runHandles[taskID] else { return }
        pausingTaskIDs.insert(taskID)
        if handle.togglePause() {
            pausedTaskIDs.insert(taskID)
        } else {
            pausedTaskIDs.remove(taskID)
        }
        pausingTaskIDs.remove(taskID)
        syncIconRotationToActivity()
    }

    /// Terminates one task's in-flight rsync process, independently of any other task's run.
    /// `stoppingTaskIDs` stays set until `finishRun` — rsync can take a moment to actually exit.
    func stopTask(_ taskID: UUID) {
        guard runHandles[taskID] != nil else { return }
        stoppingTaskIDs.insert(taskID)
        runHandles[taskID]?.cancel()
    }

    func pauseAllRunningTasks() {
        for task in tasks where runStatus(for: task.id) == .running && !pausedTaskIDs.contains(task.id) {
            togglePauseTask(task.id)
        }
    }

    func resumeAllPausedTasks() {
        for taskID in pausedTaskIDs {
            togglePauseTask(taskID)
        }
    }

    func toggleGlobalPause() {
        if isAnyTaskPaused {
            resumeAllPausedTasks()
        } else {
            pauseAllRunningTasks()
        }
    }

    func stopAllTasks() {
        for task in tasks where runStatus(for: task.id) == .running {
            stopTask(task.id)
        }
    }

    private func finishRun(taskID: UUID, ok: Bool, handle: RunHandle, warnings: [String], startDate: Date) {
        let now = Date()
        let status: RunStatus = handle.isCancelled ? .stopped(now) : (ok ? .succeeded(now) : .failed(now))
        runStatuses[taskID] = status
        if case .failed = status, !warnings.isEmpty {
            taskFailureReasons[taskID] = warnings
        } else {
            taskFailureReasons[taskID] = nil
        }
        let outcome: RunSummary.Outcome = handle.isCancelled ? .stopped : (ok ? .succeeded : .failed)
        lastRunSummaries[taskID] = RunSummary(
            outcome: outcome,
            date: now,
            duration: now.timeIntervalSince(startDate),
            bytesTransferred: progressTracker.progress(for: taskID)?.bytesDone ?? 0
        )
        pausedTaskIDs.remove(taskID)
        pausingTaskIDs.remove(taskID)
        stoppingTaskIDs.remove(taskID)
        runHandles[taskID] = nil
        progressTracker.clear(taskID)
        refreshLog()
        syncIconRotationToActivity()
    }

    /// Reflects actual transfer activity in the shared icon clock: spins while
    /// at least one task is running-and-not-paused, freezes in place (without
    /// resetting) if every still-running task is paused, and stops/resets once
    /// none are running. `iconRotation` is a single app-wide clock shared by
    /// every task, so this always has to look at overall state, not just the
    /// one task that just changed.
    private func syncIconRotationToActivity() {
        let runningTaskIDs = tasks.map(\.id).filter { runStatus(for: $0) == .running }
        guard !runningTaskIDs.isEmpty else {
            iconRotation.stop()
            return
        }
        if runningTaskIDs.contains(where: { !pausedTaskIDs.contains($0) }) {
            iconRotation.start()
        } else {
            iconRotation.pause()
        }
    }
}
