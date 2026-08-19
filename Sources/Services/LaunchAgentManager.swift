import Foundation
import Darwin

/// Installs/removes a per-user LaunchAgent that relaunches this app's
/// executable with `--run <task-id>` on a schedule. Each sync task gets
/// its own independently-scheduled LaunchAgent. This replaces the crontab
/// approach in rsync_backup.sh (cron on modern macOS has Full Disk
/// Access/permission quirks the script itself warns about).
enum LaunchAgentManager {

    private static func label(for taskID: UUID) -> String {
        "com.wolfcare.syncmanager.backup.\(taskID.uuidString.lowercased())"
    }

    private static func plistURL(for taskID: UUID) -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label(for: taskID)).plist")
    }

    static func install(taskID: UUID, schedule: ScheduleKind) throws {
        try? remove(taskID: taskID)
        guard schedule != .off else { return }

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]

        var plist: [String: Any] = [
            "Label": label(for: taskID),
            "ProgramArguments": [executablePath, "--run", taskID.uuidString],
            "RunAtLoad": false,
            "StandardOutPath": ConfigIO.logFile.path,
            "StandardErrorPath": ConfigIO.logFile.path,
        ]

        switch schedule {
        case .off:
            return
        case .hourly:
            plist["StartCalendarInterval"] = ["Minute": 0]
        case .daily(let hour, let minute):
            plist["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
        case .weekly(let weekday, let hour, let minute):
            plist["StartCalendarInterval"] = ["Weekday": weekday, "Hour": hour, "Minute": minute]
        case .everyNMinutes(let n):
            plist["StartInterval"] = max(60, n * 60)
        }

        let url = plistURL(for: taskID)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)

        try runLaunchctl(["bootstrap", "gui/\(getuid())", url.path])
    }

    static func remove(taskID: UUID) throws {
        let url = plistURL(for: taskID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        _ = try? runLaunchctl(["bootout", "gui/\(getuid())/\(label(for: taskID))"])
        try FileManager.default.removeItem(at: url)
    }

    static func installedSchedule(taskID: UUID) -> ScheduleKind? {
        guard let data = try? Data(contentsOf: plistURL(for: taskID)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        if let interval = plist["StartInterval"] as? Int {
            return .everyNMinutes(max(1, interval / 60))
        }
        if let calendar = plist["StartCalendarInterval"] as? [String: Int] {
            let hour = calendar["Hour"]
            let minute = calendar["Minute"] ?? 0
            let weekday = calendar["Weekday"]
            if let weekday {
                return .weekly(weekday: weekday, hour: hour ?? 0, minute: minute)
            }
            if let hour {
                return .daily(hour: hour, minute: minute)
            }
            if calendar["Minute"] != nil {
                return .hourly
            }
        }
        return nil
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
