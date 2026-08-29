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
    /// this process cannot actually list the contents of right now.
    static func unreadableMountedVolumeNames() -> [String] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            return readable ? nil : name
        }
    }
}
