import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject private var store: BackupStore
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
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Quit Imitor Sync Manager") {
            NSApp.terminate(nil)
        }
    }

    private func statusLine(for task: SyncTask) -> String {
        switch store.runStatus(for: task.id) {
        case .idle:
            return "\(task.name) — \(task.schedule.summary)"
        case .running:
            return "\(task.name) — \(store.isTaskPaused(task.id) ? "Paused" : "Syncing…")"
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
