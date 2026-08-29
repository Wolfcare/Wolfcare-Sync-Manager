import SwiftUI

struct RunTaskButton: View {
    let taskID: UUID
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        Button {
            store.runTaskNow(taskID)
        } label: {
            if store.runStatus(for: taskID) == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(2)
                    .frame(width: 34, height: 34)
            } else {
                Label("Run Now", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .font(.system(size: 26))
        .disabled(!store.canRunTask(taskID))
        .help(store.canRunTask(taskID) ? "Run this backup now" : "Add a source and a reachable destination first")
    }
}
