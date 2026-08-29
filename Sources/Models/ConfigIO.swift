import Foundation

/// Reads and writes the same on-disk config format as the original
/// `rsync_backup.sh` script (~/.config/rsync_backup/...), so the GUI app
/// and the shell script stay interchangeable.
enum ConfigIO {

    static let configDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/rsync_backup", isDirectory: true)

    static let dirsFile = configDir.appendingPathComponent("dirs.list")
    static let confFile = configDir.appendingPathComponent("settings.conf")
    static let logFile = configDir.appendingPathComponent("backup.log")
    static let tasksFile = configDir.appendingPathComponent("tasks.json")

    static func ensureConfigFilesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: nil)
        }
    }

    // MARK: - Sync tasks (tasks.json)

    static func loadTasks() -> [SyncTask] {
        if let data = try? Data(contentsOf: tasksFile),
           let tasks = try? JSONDecoder().decode([SyncTask].self, from: data) {
            return tasks
        }
        // First run: migrate a single-task config written by rsync_backup.sh, if any.
        let legacySources = loadLegacySources()
        let legacyDestination = loadLegacyDestination()
        guard !legacySources.isEmpty || legacyDestination != nil else { return [] }
        let migrated = [SyncTask(
            name: "My Backup",
            sources: legacySources.map { SourceEntry(path: $0, copyMode: .contentsOnly) },
            destination: legacyDestination
        )]
        saveTasks(migrated)
        return migrated
    }

    static func saveTasks(_ tasks: [SyncTask]) {
        ensureConfigFilesExist()
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksFile)
    }

    // MARK: - Legacy single-task config (dirs.list / settings.conf), read-only

    private static func loadLegacySources() -> [String] {
        guard let text = try? String(contentsOf: dirsFile, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func loadLegacyDestination() -> String? {
        guard let text = try? String(contentsOf: confFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("DEST_ROOT=") else { continue }
            var value = String(trimmed.dropFirst("DEST_ROOT=".count))
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - Log

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func appendLog(_ message: String) {
        ensureConfigFilesExist()
        let timestamp = logDateFormatter.string(from: Date())
        let line = "\(timestamp)  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFile)
        }
    }

    static func clearLog() {
        ensureConfigFilesExist()
        try? Data().write(to: logFile)
    }

    static func readRecentLogLines(limit: Int = 200) -> String {
        guard let data = try? Data(contentsOf: logFile) else {
            return "(no log yet)"
        }
        // Lossy-decode rather than strict UTF-8: a single stray byte anywhere
        // in the file (e.g. a legacy-encoded filename echoed verbatim from a
        // network share's rsync output) would otherwise fail the whole read
        // and silently show "(no log yet)" despite the file having content.
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(limit)
        return tail.joined(separator: "\n")
    }
}
