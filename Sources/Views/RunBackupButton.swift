import SwiftUI

struct RunTaskButton: View {
    let taskID: UUID
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        Button {
            store.runTaskNow(taskID)
        } label: {
            if store.runStatus(for: taskID) == .running {
                ProgressView().controlSize(.small)
            } else {
                Label("Run Now", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(!store.canRunTask(taskID))
        .help(store.canRunTask(taskID) ? "Run this backup now" : "Add a source and a reachable destination first")
    }
}
