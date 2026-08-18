import SwiftUI

struct RunBackupButton: View {
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        Button {
            store.runBackupNow()
        } label: {
            if store.runStatus == .running {
                ProgressView().controlSize(.small)
            } else {
                Label("Run Backup Now", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(!store.canRunBackup)
        .help(store.canRunBackup ? "Run a backup now" : "Add a source and a reachable destination first")
    }
}
