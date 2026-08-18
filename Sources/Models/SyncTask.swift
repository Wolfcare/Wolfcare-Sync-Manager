import Foundation

/// One independent backup job: a set of source directories, a destination,
/// and its own schedule. The app can manage several of these at once, each
/// with its own LaunchAgent.
struct SyncTask: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var sources: [String]
    var destination: String?
    var schedule: ScheduleKind

    init(
        id: UUID = UUID(),
        name: String,
        sources: [String] = [],
        destination: String? = nil,
        schedule: ScheduleKind = .off
    ) {
        self.id = id
        self.name = name
        self.sources = sources
        self.destination = destination
        self.schedule = schedule
    }
}
