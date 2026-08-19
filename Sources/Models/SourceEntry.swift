import Foundation

/// How a source directory is placed under the destination root.
enum CopyMode: String, Codable, Equatable {
    /// rsync src/ dest/ — copies the contents of the folder directly into
    /// the destination root (original rsync_backup.sh behaviour).
    case contentsOnly
    /// rsync src dest/ — copies the folder itself as a subdirectory of
    /// the destination, so sources with overlapping filenames don't collide.
    case folderAndContents
}

struct SourceEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var copyMode: CopyMode

    init(id: UUID = UUID(), path: String, copyMode: CopyMode = .contentsOnly) {
        self.id = id
        self.path = path
        self.copyMode = copyMode
    }
}
