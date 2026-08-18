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

    @Published private(set) var sources: [String] = []
    @Published private(set) var destination: String?
    @Published private(set) var schedule: ScheduleKind = .off
    @Published private(set) var runStatus: RunStatus = .idle
    @Published private(set) var logText: String = "(no log yet)"
    @Published var lastError: String?

    init() {
        ConfigIO.ensureConfigFilesExist()
        reloadAll()
    }

    func reloadAll() {
        sources = ConfigIO.loadSources()
        destination = ConfigIO.loadDestination()
        schedule = LaunchAgentManager.installedSchedule() ?? .off
        refreshLog()
    }

    var isDestinationReachable: Bool {
        guard let destination else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: destination, isDirectory: &isDir) && isDir.boolValue
    }

    var canRunBackup: Bool {
        !sources.isEmpty && isDestinationReachable && runStatus != .running
    }

    // MARK: - Sources

    func addSource(_ path: String) {
        var resolved = path
        if resolved.hasSuffix("/") { resolved.removeLast() }
        guard !resolved.isEmpty, !sources.contains(resolved) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else { return }
        sources.append(resolved)
        ConfigIO.saveSources(sources)
    }

    func removeSources(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        ConfigIO.saveSources(sources)
    }

    // MARK: - Destination

    func setDestination(_ path: String) {
        var resolved = path
        if resolved.hasSuffix("/") { resolved.removeLast() }
        guard !resolved.isEmpty else { return }
        destination = resolved
        ConfigIO.saveDestination(resolved)
    }

    // MARK: - Schedule

    func applySchedule(_ kind: ScheduleKind) {
        do {
            try LaunchAgentManager.install(schedule: kind)
            schedule = kind
            lastError = nil
        } catch {
            lastError = "Could not install schedule: \(error.localizedDescription)"
        }
    }

    func clearSchedule() {
        do {
            try LaunchAgentManager.remove()
            schedule = .off
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

    func runBackupNow() {
        guard canRunBackup else { return }
        runStatus = .running
        let sourcesSnapshot = sources
        guard let destinationSnapshot = destination else { return }

        Task.detached(priority: .userInitiated) {
            let ok = RsyncRunner.runBackup(
                sources: sourcesSnapshot,
                destinationRoot: destinationSnapshot,
                log: ConfigIO.appendLog
            )
            await self.finishRun(ok: ok)
        }
    }

    private func finishRun(ok: Bool) {
        runStatus = ok ? .succeeded(Date()) : .failed(Date())
        refreshLog()
    }
}
