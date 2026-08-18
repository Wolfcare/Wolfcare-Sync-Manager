import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject private var store: BackupStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        Divider()

        Button("Run Backup Now") {
            store.runBackupNow()
        }
        .disabled(!store.canRunBackup)

        Button("Open Wolfcare Sync Manager…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Quit Wolfcare Sync Manager") {
            NSApp.terminate(nil)
        }
    }

    private var statusLine: String {
        switch store.runStatus {
        case .idle:
            return "Idle · \(store.schedule.summary)"
        case .running:
            return "Syncing…"
        case .succeeded(let date):
            return "Last backup OK at \(Self.timeFormatter.string(from: date))"
        case .failed(let date):
            return "Last backup FAILED at \(Self.timeFormatter.string(from: date))"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
