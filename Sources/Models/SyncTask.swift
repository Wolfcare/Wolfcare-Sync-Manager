import Foundation

/// One independent backup job: a set of source directories, a destination,
/// and its own schedule. The app can manage several of these at once, each
/// with its own LaunchAgent.
struct SyncTask: Identifiable, Equatable {
    var id: UUID
    var name: String
    var sources: [SourceEntry]
    var destination: String?
    var schedule: ScheduleKind

    init(
        id: UUID = UUID(),
        name: String,
        sources: [SourceEntry] = [],
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

extension SyncTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, sources, destination, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        schedule = try container.decode(ScheduleKind.self, forKey: .schedule)

        // Sources used to be a plain [String] of paths; migrate those to
        // SourceEntry (defaulting to the original contents-only behavior)
        // if the new [SourceEntry] shape doesn't decode.
        if let entries = try? container.decode([SourceEntry].self, forKey: .sources) {
            sources = entries
        } else {
            let legacyPaths = try container.decode([String].self, forKey: .sources)
            sources = legacyPaths.map { SourceEntry(path: $0, copyMode: .contentsOnly) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encode(schedule, forKey: .schedule)
    }
}
