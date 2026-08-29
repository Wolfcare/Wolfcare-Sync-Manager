import Foundation

/// Holds live per-task sync progress separately from `BackupStore`.
/// Progress updates arrive as often as every ~150ms while a task is running;
/// keeping them off `BackupStore`'s `@Published` surface means the sidebar
/// (which only observes `BackupStore` and never reads progress) doesn't get
/// invalidated and rebuilt on every tick — that churn was making the sidebar's
/// List selection unresponsive while a sync was in progress.
@MainActor
final class SyncProgressTracker: ObservableObject {
    @Published private(set) var byTask: [UUID: RsyncRunner.SyncProgress] = [:]

    func set(_ progress: RsyncRunner.SyncProgress, for taskID: UUID) {
        byTask[taskID] = progress
    }

    func clear(_ taskID: UUID) {
        byTask[taskID] = nil
    }

    func progress(for taskID: UUID) -> RsyncRunner.SyncProgress? {
        byTask[taskID]
    }
}
