import Foundation

/// Equivalent of `rsync_backup.sh run` — invoked when the app's executable
/// is launched with `--run` (by the LaunchAgent, or from a terminal).
/// Performs one backup pass with no UI and exits.
enum HeadlessRunner {
    static func run() -> Bool {
        ConfigIO.ensureConfigFilesExist()

        let sources = ConfigIO.loadSources()
        guard let destination = ConfigIO.loadDestination(), !destination.isEmpty else {
            ConfigIO.appendLog("ABORT: destination not configured")
            return false
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination, isDirectory: &isDir), isDir.boolValue else {
            ConfigIO.appendLog("ABORT: destination \(destination) not reachable")
            return false
        }
        guard !sources.isEmpty else {
            ConfigIO.appendLog("ABORT: no source directories configured")
            return false
        }

        return RsyncRunner.runBackup(sources: sources, destinationRoot: destination, log: ConfigIO.appendLog)
    }
}
