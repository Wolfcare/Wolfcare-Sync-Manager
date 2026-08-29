import Foundation

/// Runs rsync the same way rsync_backup.sh does: archive mode, checksum
/// comparison, and a timestamped --backup-dir under DEST_ROOT/.versions
/// so overwritten files are preserved instead of lost.
enum RsyncRunner {

    /// A snapshot of how far a multi-source backup run has gotten, in bytes,
    /// so the UI can show a progress bar and an estimated time remaining.
    struct SyncProgress: Equatable {
        let sourceIndex: Int
        let sourceCount: Int
        let bytesDone: Int64
        let bytesTotal: Int64
        let etaSeconds: Int?

        var fraction: Double {
            guard bytesTotal > 0 else { return 0 }
            return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
        }
    }

    static func locateRsyncExecutable() -> String {
        // Prefer a Homebrew-installed rsync (3.1+) when present: it supports
        // --info=progress2, which is what makes the aggregate progress bar
        // possible. macOS's own /usr/bin/rsync is a pre-3.0 BSD build.
        let candidates = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]
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
    /// If `handle` is cancelled (via `RunHandle.cancel()`) partway through,
    /// the in-flight rsync process is terminated and remaining sources are skipped.
    /// `onProgress` is invoked (from a background thread) as rsync reports bytes
    /// transferred, after an upfront dry-run pass establishes the total size to sync.
    @discardableResult
    static func runBackup(
        sources: [SourceEntry],
        destinationRoot: String,
        handle: RunHandle? = nil,
        onProgress: ((SyncProgress) -> Void)? = nil,
        log: (String) -> Void
    ) -> Bool {
        let rsyncPath = locateRsyncExecutable()
        let timestamp = timestampFormatter.string(from: Date())
        let versionRoot = (destinationRoot as NSString).appendingPathComponent(".versions/\(timestamp)")

        log("===== Backup run started (\(timestamp)) =====")

        let destSlash = destinationRoot.hasSuffix("/") ? destinationRoot : destinationRoot + "/"
        try? FileManager.default.createDirectory(atPath: destinationRoot, withIntermediateDirectories: true)

        let eligibleSources = sources.filter { entry in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir) && isDir.boolValue
        }

        log("Calculating sync size…")
        let perSourceBytes = eligibleSources.map { entry in
            estimateTransferBytes(for: entry, destSlash: destSlash, rsyncPath: rsyncPath)
        }
        let totalBytes = perSourceBytes.reduce(0, +)
        let useProgress2 = supportsProgress2(rsyncPath: rsyncPath)
        let startDate = Date()

        var allSucceeded = true
        var bytesDoneBeforeThisSource: Int64 = 0

        for entry in sources {
            if handle?.isCancelled == true {
                log("STOPPED (by user) before \(entry.path)")
                allSucceeded = false
                break
            }

            let src = entry.path
            guard let sourceIndex = eligibleSources.firstIndex(where: { $0.id == entry.id }) else {
                log("SKIP (missing) \(src)")
                continue
            }

            let rsyncSource = rsyncSourcePath(for: entry)
            let modeDescription: String
            switch entry.copyMode {
            case .contentsOnly: modeDescription = "contents only"
            case .folderAndContents: modeDescription = "folder + contents"
            }

            log("Syncing \(rsyncSource) -> \(destSlash) [\(modeDescription)]")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: rsyncPath)
            var arguments = [
                "-a", "-c", "--itemize-changes",
                "--backup", "--backup-dir=\(versionRoot)"
            ]
            arguments += useProgress2 ? ["--info=progress2"] : ["--progress"]
            arguments += [rsyncSource, destSlash]
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var outputBuffer = Data()
            var collectedLines: [String] = []
            var sourceCompletedFilesBytes: Int64 = 0
            var currentFileBytes: Int64 = 0
            var lastProgressPost = Date.distantPast

            func postProgress(_ liveBytes: Int64, force: Bool = false) {
                guard onProgress != nil, totalBytes > 0 else { return }
                let now = Date()
                guard force || now.timeIntervalSince(lastProgressPost) > 0.15 else { return }
                lastProgressPost = now
                let overallDone = min(bytesDoneBeforeThisSource + liveBytes, totalBytes)
                let elapsed = now.timeIntervalSince(startDate)
                let rate = elapsed > 0 ? Double(overallDone) / elapsed : 0
                let remaining = totalBytes - overallDone
                let eta = rate > 0 ? Int(Double(remaining) / rate) : nil
                onProgress?(SyncProgress(
                    sourceIndex: sourceIndex + 1,
                    sourceCount: eligibleSources.count,
                    bytesDone: overallDone,
                    bytesTotal: totalBytes,
                    etaSeconds: eta
                ))
            }

            let pipeClosedSemaphore = DispatchSemaphore(value: 0)
            pipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else {
                    pipeClosedSemaphore.signal()
                    return
                }
                outputBuffer.append(data)
                for line in extractLines(from: &outputBuffer) {
                    guard !line.isEmpty else { continue }
                    if let bytes = parseProgressBytes(line) {
                        currentFileBytes = bytes
                        postProgress(sourceCompletedFilesBytes + currentFileBytes)
                    } else if looksLikeItemizeLine(line) {
                        sourceCompletedFilesBytes += currentFileBytes
                        currentFileBytes = 0
                    }
                    collectedLines.append(line)
                }
            }

            do {
                try process.run()
                handle?.attach(process)
                // Wait for EOF on the pipe (rsync closing stdout/stderr) rather than
                // waitUntilExit() first, so the readabilityHandler is guaranteed to be
                // done mutating outputBuffer/collectedLines before we touch them below.
                pipeClosedSemaphore.wait()
                pipe.fileHandleForReading.readabilityHandler = nil
                process.waitUntilExit()
                handle?.detach()
                if !outputBuffer.isEmpty, let leftover = String(data: outputBuffer, encoding: .utf8),
                   !leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    collectedLines.append(leftover)
                }
                let trimmed = collectedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { log(trimmed) }

                if handle?.isCancelled == true {
                    log("STOPPED \(src) (by user, rsync exit \(process.terminationStatus))")
                    allSucceeded = false
                } else if process.terminationStatus == 0 {
                    log("OK   \(src) (rsync exit 0)")
                } else {
                    log("FAIL \(src) (rsync exit \(process.terminationStatus))")
                    allSucceeded = false
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                log("FAIL \(src) (could not launch rsync: \(error.localizedDescription))")
                allSucceeded = false
            }

            // Skip on cancellation: the source didn't actually finish, so crediting
            // its full byte budget would jump the bar to 100% right as it stops.
            if handle?.isCancelled != true {
                bytesDoneBeforeThisSource += perSourceBytes[sourceIndex]
                postProgress(0, force: true)
            }
        }

        removeEmptyDirectoriesRecursively(at: versionRoot)
        log(handle?.isCancelled == true ? "===== Backup run stopped by user =====" : "===== Backup run finished =====")
        return allSucceeded
    }

    private static func rsyncSourcePath(for entry: SourceEntry) -> String {
        switch entry.copyMode {
        case .contentsOnly:
            return entry.path.hasSuffix("/") ? entry.path : entry.path + "/"
        case .folderAndContents:
            return entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        }
    }

    /// Dry-runs one source through rsync with `--stats` to find out how many bytes
    /// it would actually transfer (honoring the same checksum comparison and
    /// versioning args as the real run), without writing anything.
    private static func estimateTransferBytes(for entry: SourceEntry, destSlash: String, rsyncPath: String) -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rsyncPath)
        process.arguments = ["-a", "-c", "--dry-run", "--stats", rsyncSourcePath(for: entry), destSlash]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return 0 }
            return parseTotalTransferSize(from: text)
        } catch {
            return 0
        }
    }

    private static func parseTotalTransferSize(from statsOutput: String) -> Int64 {
        guard let range = statsOutput.range(
            of: #"Total transferred file size:\s*[\d,]+"#,
            options: .regularExpression
        ) else { return 0 }
        let digits = statsOutput[range].filter(\.isNumber)
        return Int64(digits) ?? 0
    }

    private static func supportsProgress2(rsyncPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rsyncPath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8),
                  let range = text.range(of: #"version (\d+)\.(\d+)"#, options: .regularExpression)
            else { return false }
            let numbers = text[range].split(separator: " ").last.map(String.init) ?? ""
            let parts = numbers.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2 else { return false }
            return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 1)
        } catch {
            return false
        }
    }

    /// Splits a growing buffer on `\r` or `\n` (rsync uses `\r` to redraw its
    /// progress line in place), returning completed segments and leaving any
    /// trailing partial line in `buffer` for the next chunk.
    private static func extractLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let index = buffer.firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
            let lineData = buffer[buffer.startIndex..<index]
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
            buffer.removeSubrange(buffer.startIndex...index)
        }
        return lines
    }

    /// Matches the leading byte count of an rsync progress line, e.g.
    /// "     1,234,567  45%    2.34MB/s    0:00:03 (xfr#5, to-chk=10/56)" —
    /// the same leading field appears whether it's per-file (--progress) or
    /// aggregate-for-the-source (--info=progress2).
    private static func parseProgressBytes(_ line: String) -> Int64? {
        guard let range = line.range(of: #"^\s*[\d,]+(?=\s+\d+%)"#, options: .regularExpression) else { return nil }
        let digits = line[range].filter(\.isNumber)
        return Int64(digits)
    }

    /// An `--itemize-changes` line (the one rsync prints when a file starts
    /// transferring) starts with a flag character, never whitespace or a digit.
    private static func looksLikeItemizeLine(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return !first.isWhitespace && !first.isNumber
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
