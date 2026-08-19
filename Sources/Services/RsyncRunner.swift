import Foundation

/// Runs rsync the same way rsync_backup.sh does: archive mode, checksum
/// comparison, and a timestamped --backup-dir under DEST_ROOT/.versions
/// so overwritten files are preserved instead of lost.
enum RsyncRunner {

    static func locateRsyncExecutable() -> String {
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/rsync"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Runs synchronously (intended to be called from a background thread/Task).
    /// Returns true only if every source directory synced without error.
    @discardableResult
    static func runBackup(
        sources: [SourceEntry],
        destinationRoot: String,
        log: (String) -> Void
    ) -> Bool {
        let rsyncPath = locateRsyncExecutable()
        let timestamp = timestampFormatter.string(from: Date())
        let versionRoot = (destinationRoot as NSString).appendingPathComponent(".versions/\(timestamp)")

        log("===== Backup run started (\(timestamp)) =====")
        var allSucceeded = true

        for entry in sources {
            let src = entry.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue else {
                log("SKIP (missing) \(src)")
                continue
            }

            let destSlash = destinationRoot.hasSuffix("/") ? destinationRoot : destinationRoot + "/"
            try? FileManager.default.createDirectory(atPath: destinationRoot, withIntermediateDirectories: true)

            let rsyncSource: String
            let modeDescription: String
            switch entry.copyMode {
            case .contentsOnly:
                rsyncSource = src.hasSuffix("/") ? src : src + "/"
                modeDescription = "contents only"
            case .folderAndContents:
                rsyncSource = src.hasSuffix("/") ? String(src.dropLast()) : src
                modeDescription = "folder + contents"
            }

            log("Syncing \(rsyncSource) -> \(destSlash) [\(modeDescription)]")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: rsyncPath)
            process.arguments = [
                "-a", "-c", "--itemize-changes",
                "--backup", "--backup-dir=\(versionRoot)",
                rsyncSource, destSlash
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let output = String(data: outputData, encoding: .utf8) {
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { log(trimmed) }
                }
                if process.terminationStatus == 0 {
                    log("OK   \(src) (rsync exit 0)")
                } else {
                    log("FAIL \(src) (rsync exit \(process.terminationStatus))")
                    allSucceeded = false
                }
            } catch {
                log("FAIL \(src) (could not launch rsync: \(error.localizedDescription))")
                allSucceeded = false
            }
        }

        removeEmptyDirectoriesRecursively(at: versionRoot)
        log("===== Backup run finished =====")
        return allSucceeded
    }

    /// Equivalent of `find "$version_root" -type d -empty -delete`.
    private static func removeEmptyDirectoriesRecursively(at path: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }

        if let children = try? fm.contentsOfDirectory(atPath: path) {
            for child in children {
                removeEmptyDirectoriesRecursively(at: (path as NSString).appendingPathComponent(child))
            }
        }
        if let remaining = try? fm.contentsOfDirectory(atPath: path), remaining.isEmpty {
            try? fm.removeItem(atPath: path)
        }
    }
}
