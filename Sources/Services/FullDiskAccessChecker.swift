import Foundation

/// Full Disk Access is an all-or-nothing macOS permission (System Settings ›
/// Privacy & Security › Full Disk Access) this non-sandboxed app needs to
/// reliably read/write arbitrary source and destination folders — including
/// ones on external or network volumes, which macOS can gate independently
/// of Full Disk Access via its own "Removable Volumes" / "Network Volumes"
/// TCC categories.
enum FullDiskAccessChecker {
    /// Every Mac has this file; actually reading it requires Full Disk Access.
    /// There's no direct TCC query API, so attempting a real read (not just a
    /// permission-bits check) is the standard way non-sandboxed apps probe for it.
    private static let probePath = "/Library/Application Support/com.apple.TCC/TCC.db"

    static var hasFullDiskAccess: Bool {
        FileManager.default.contents(atPath: probePath) != nil
    }

    /// Display names of currently mounted volumes (internal, external, network)
    /// this process cannot actually list the contents of right now. Each volume
    /// is probed with a timeout so a stale/unresponsive network mount can't hang
    /// the whole check — a volume that doesn't answer in time is skipped rather
    /// than flagged, since an unresponsive mount isn't necessarily a permissions problem.
    static func unreadableMountedVolumeNames(perVolumeTimeout: TimeInterval = 3) -> [String] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url -> String? in
            guard let readable = isReadable(url.path, timeout: perVolumeTimeout), !readable else { return nil }
            return (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
        }
    }

    /// nil means "didn't answer within the timeout" — inconclusive, not a denial.
    private static func isReadable(_ path: String, timeout: TimeInterval) -> Bool? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool?
        DispatchQueue.global(qos: .utility).async {
            result = (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return result
    }
}
