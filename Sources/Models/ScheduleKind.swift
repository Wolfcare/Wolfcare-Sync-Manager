import Foundation

/// Automatic-backup schedule, installed as a launchd LaunchAgent instead
/// of the crontab entry the original script used.
enum ScheduleKind: Equatable, Codable {
    case off
    case hourly
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int) // weekday: 0/7 = Sunday, matches launchd
    case everyNMinutes(Int)

    var summary: String {
        switch self {
        case .off:
            return "No automatic schedule"
        case .hourly:
            return "Every hour, on the hour"
        case .daily(let hour, let minute):
            return String(format: "Every day at %02d:%02d", hour, minute)
        case .weekly(let weekday, let hour, let minute):
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let name = names[weekday % 7]
            return String(format: "Every %@ at %02d:%02d", name, hour, minute)
        case .everyNMinutes(let n):
            return "Every \(n) minute\(n == 1 ? "" : "s")"
        }
    }
}
