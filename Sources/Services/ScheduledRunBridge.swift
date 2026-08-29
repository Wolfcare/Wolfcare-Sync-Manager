import Foundation
import AppKit

/// A scheduled run fires as a brand-new headless process (see main.swift's
/// `--run` path) with no connection to any already-open GUI instance, so a
/// scheduled backup used to run invisibly — no progress bar, no spinning
/// menu bar icon, nothing — even while the app window was sitting right
/// there. This hands the run to the running GUI instance instead, so it goes
/// through the same `BackupStore.runTaskNow` path a manual run does and gets
/// the same visible feedback. Only falls back to a fully headless run when no
/// GUI instance is actually open.
enum ScheduledRunBridge {
    private static let notificationName = Notification.Name("com.wolfcare.syncmanager.scheduledRunRequested")
    private static let taskIDKey = "taskID"

    /// Called from the `--run` launch path. Returns true if a running GUI
    /// instance was handed the request (the caller should skip running the
    /// sync itself), false if there's no GUI instance to hand it to.
    static func forwardToRunningAppIfPossible(taskID: UUID) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.wolfcare.SyncManager"
        let isGUIRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard isGUIRunning else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: [taskIDKey: taskID.uuidString],
            deliverImmediately: true
        )
        return true
    }

    /// Called once at GUI startup so a scheduled run forwarded by a `--run`
    /// process (while this GUI instance is already open) gets picked up.
    static func observeIncomingRuns(_ handler: @escaping @MainActor (UUID) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let idString = notification.userInfo?[taskIDKey] as? String,
                let taskID = UUID(uuidString: idString)
            else { return }
            Task { @MainActor in
                handler(taskID)
            }
        }
    }
}
