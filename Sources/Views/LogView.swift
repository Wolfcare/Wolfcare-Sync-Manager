import SwiftUI
import AppKit
import Combine

struct LogView: View {
    @EnvironmentObject private var store: BackupStore
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.highlight2)
                Spacer()
                Button {
                    store.refreshLog()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(minWidth: 68)
                }
                .buttonStyle(.chrome)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigIO.logFile])
                } label: {
                    Label("Open", systemImage: "folder")
                        .frame(minWidth: 68)
                }
                .buttonStyle(.chrome)
                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear Log", systemImage: "trash")
                        .frame(minWidth: 68)
                }
                .buttonStyle(.chrome)
            }

            ScrollView {
                Text(store.logText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.highlight1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Theme.charcoalDeep)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)))
        }
        .onAppear { store.refreshLog() }
        .onReceive(refreshTimer) { _ in store.refreshLog() }
        .confirmationDialog(
            "Clear the activity log?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) { store.clearLog() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes the log file's contents. It can't be undone.")
        }
    }
}
