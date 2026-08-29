import Foundation
import Combine

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
    @Published private(set) var logText: String = "(no log yet)"
    @Published var lastError: String?
    @Published var fullDiskAccessWarning: String?

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
        refreshLog()
        checkFullDiskAccess()
    }

    // MARK: - Permissions

    /// Run at launch so a missing permission surfaces immediately rather than
    /// as a mysterious backup failure later. Full Disk Access is all-or-nothing,
    /// but macOS can additionally gate individual removable/network volumes, so
    /// every currently mounted volume is probed too. Runs off the main thread —
    /// a stale network mount could otherwise stall app launch on the directory read.
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

    private func persist() {
        ConfigIO.saveTasks(tasks)
    }

    // MARK: - Tasks

    @discardableResult
    func addTask() -> UUID {
        let task = SyncTask(name: "Backup \(tasks.count + 1)")
        tasks.append(task)
        runStatuses[task.id] = .idle
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

    // MARK: - Run

    func runTaskNow(_ taskID: UUID) {
        guard canRunTask(taskID), let task = tasks.first(where: { $0.id == taskID }) else { return }
        let handle = RunHandle()
        runHandles[taskID] = handle
        pausedTaskIDs.remove(taskID)
        progressTracker.clear(taskID)
        runStatuses[taskID] = .running
        iconRotation.start()
        Task.detached(priority: .userInitiated) {
            let ok = HeadlessRunner.run(task: task, handle: handle) { progress in
                Task { @MainActor in
                    self.progressTracker.set(progress, for: taskID)
                }
            }
            await self.finishRun(taskID: taskID, ok: ok, handle: handle)
        }
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
        if handle.togglePause() {
            pausedTaskIDs.insert(taskID)
        } else {
            pausedTaskIDs.remove(taskID)
        }
    }

    /// Terminates one task's in-flight rsync process, independently of any other task's run.
    func stopTask(_ taskID: UUID) {
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

    private func finishRun(taskID: UUID, ok: Bool, handle: RunHandle) {
        runStatuses[taskID] = handle.isCancelled ? .stopped(Date()) : (ok ? .succeeded(Date()) : .failed(Date()))
        pausedTaskIDs.remove(taskID)
        runHandles[taskID] = nil
        progressTracker.clear(taskID)
        refreshLog()

        // Only stop the icon animation once every in-flight task has
        // settled — `runAllTasksNow` can have several running concurrently.
        guard !runStatuses.values.contains(.running) else { return }
        iconRotation.stop()
    }
}
