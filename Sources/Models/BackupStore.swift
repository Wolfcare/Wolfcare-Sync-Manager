import Foundation
import Combine

@MainActor
final class BackupStore: ObservableObject {

    enum RunStatus: Equatable {
        case idle
        case running
        case succeeded(Date)
        case failed(Date)
    }

    @Published private(set) var tasks: [SyncTask] = []
    @Published private(set) var runStatuses: [UUID: RunStatus] = [:]
    @Published private(set) var logText: String = "(no log yet)"
    @Published var lastError: String?

    init() {
        ConfigIO.ensureConfigFilesExist()
        tasks = ConfigIO.loadTasks()
        for task in tasks {
            runStatuses[task.id] = .idle
        }
        refreshLog()
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
        let succeededDates = statuses.compactMap { status -> Date? in
            if case .succeeded(let date) = status { return date }
            return nil
        }
        if let latestSuccess = succeededDates.max() { return .succeeded(latestSuccess) }
        return .idle
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
        guard !resolved.isEmpty, !tasks[index].sources.contains(resolved) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else { return }
        tasks[index].sources.append(resolved)
        persist()
    }

    func removeSources(at offsets: IndexSet, from taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].sources.remove(atOffsets: offsets)
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
        runStatuses[taskID] = .running
        Task.detached(priority: .userInitiated) {
            let ok = HeadlessRunner.run(task: task)
            await self.finishRun(taskID: taskID, ok: ok)
        }
    }

    func runAllTasksNow() {
        for task in tasks where canRunTask(task.id) {
            runTaskNow(task.id)
        }
    }

    private func finishRun(taskID: UUID, ok: Bool) {
        runStatuses[taskID] = ok ? .succeeded(Date()) : .failed(Date())
        refreshLog()
    }
}
