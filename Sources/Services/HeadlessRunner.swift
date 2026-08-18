import Foundation

/// Invoked when the app's executable is launched with `--run <task-id>`
/// (by that task's LaunchAgent, or from a terminal). Performs one backup
/// pass for that task with no UI and exits.
enum HeadlessRunner {
    static func run(taskID: UUID) -> Bool {
        ConfigIO.ensureConfigFilesExist()
        guard let task = ConfigIO.loadTasks().first(where: { $0.id == taskID }) else {
            ConfigIO.appendLog("ABORT: task \(taskID.uuidString) not found")
            return false
        }
        return run(task: task)
    }

    static func run(task: SyncTask) -> Bool {
        let prefix = "[\(task.name)]"

        guard let destination = task.destination, !destination.isEmpty else {
            ConfigIO.appendLog("\(prefix) ABORT: destination not configured")
            return false
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination, isDirectory: &isDir), isDir.boolValue else {
            ConfigIO.appendLog("\(prefix) ABORT: destination \(destination) not reachable")
            return false
        }
        guard !task.sources.isEmpty else {
            ConfigIO.appendLog("\(prefix) ABORT: no source directories configured")
            return false
        }

        return RsyncRunner.runBackup(sources: task.sources, destinationRoot: destination) { message in
            ConfigIO.appendLog("\(prefix) \(message)")
        }
    }
}
