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

    static func ensureConfigFilesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        for url in [dirsFile, logFile] where !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        if !fm.fileExists(atPath: confFile.path) {
            fm.createFile(atPath: confFile.path, contents: nil)
        }
    }

    // MARK: - Source directories (dirs.list, one absolute path per line)

    static func loadSources() -> [String] {
        guard let text = try? String(contentsOf: dirsFile, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func saveSources(_ sources: [String]) {
        ensureConfigFilesExist()
        let text = sources.joined(separator: "\n") + (sources.isEmpty ? "" : "\n")
        try? text.write(to: dirsFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Destination (settings.conf, shell-style DEST_ROOT="...")

    static func loadDestination() -> String? {
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

    static func saveDestination(_ path: String) {
        ensureConfigFilesExist()
        let existing = (try? String(contentsOf: confFile, encoding: .utf8)) ?? ""
        let keptLines = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("DEST_ROOT=") }
        var lines = keptLines.map(String.init)
        lines.append("DEST_ROOT=\"\(path)\"")
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: confFile, atomically: true, encoding: .utf8)
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

    static func readRecentLogLines(limit: Int = 200) -> String {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else {
            return "(no log yet)"
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(limit)
        return tail.joined(separator: "\n")
    }
}
