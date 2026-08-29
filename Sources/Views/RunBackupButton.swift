import SwiftUI

struct RunTaskButton: View {
    let taskID: UUID
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        if store.runStatus(for: taskID) == .running {
            Button {
                store.runTaskNow(taskID)
            } label: {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34, height: 34)
                    .background(Theme.chromeFill, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(true)
        } else {
            ChromeIconButton(systemImage: "arrow.triangle.2.circlepath") {
                store.runTaskNow(taskID)
            }
            .disabled(!store.canRunTask(taskID))
            .opacity(store.canRunTask(taskID) ? 1 : 0.4)
            .help(store.canRunTask(taskID) ? "Run this backup now" : "Add a source and a reachable destination first")
        }
    }
}
