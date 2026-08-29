import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject private var store: BackupStore
    @EnvironmentObject private var progressTracker: SyncProgressTracker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.tasks.isEmpty {
            Text("No sync tasks yet")
        } else {
            ForEach(store.tasks) { task in
                Button(statusLine(for: task)) {
                    store.runTaskNow(task.id)
                }
                .disabled(!store.canRunTask(task.id))
            }

            Divider()

            Button("Run All Now") {
                store.runAllTasksNow()
            }
        }

        Button("Open Imitor Sync Manager…") {
            openMainWindow()
        }

        Button("Check for Updates…") {
            // Open the main window first — the result (update available, up to
            // date, or a network error) is shown there via an alert, which needs
            // a live window to attach to.
            openMainWindow()
            store.checkForUpdates(manual: true)
        }

        Divider()

        Button("Quit Imitor Sync Manager") {
            NSApp.terminate(nil)
        }
    }

    /// Restores the Dock icon/Cmd+Tab entry (AppDelegate drops to .accessory
    /// when the last window closes, so it can hide from the Dock while still
    /// running scheduled tasks in the background) and brings the window forward.
    ///
    /// Order matters: calling `NSApp.activate` while zero windows are open
    /// triggers SwiftUI's own implicit "reopen a window" handling for
    /// `WindowGroup`, so doing that *before* `openWindow` produced two windows
    /// — one from the implicit reopen, one from the explicit call. Opening
    /// the window first, then activating (a window already exists by then,
    /// so there's nothing for the implicit path to do), avoids the duplicate.
    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func statusLine(for task: SyncTask) -> String {
        switch store.runStatus(for: task.id) {
        case .idle:
            return "\(task.name) — \(task.schedule.summary)"
        case .running:
            if store.isTaskPaused(task.id) { return "\(task.name) — Paused" }
            return "\(task.name) — \(progressTracker.progress(for: task.id) == nil ? "Calculating…" : "Running")"
        case .succeeded(let date):
            return "\(task.name) — OK at \(Self.timeFormatter.string(from: date))"
        case .failed(let date):
            return "\(task.name) — FAILED at \(Self.timeFormatter.string(from: date))"
        case .stopped(let date):
            return "\(task.name) — Stopped at \(Self.timeFormatter.string(from: date))"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
