import SwiftUI
import AppKit
import Combine

struct LogView: View {
    @EnvironmentObject private var store: BackupStore
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.title2.bold())
                Spacer()
                Button {
                    store.refreshLog()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigIO.logFile])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            ScrollView {
                Text(store.logText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
        }
        .onAppear { store.refreshLog() }
        .onReceive(refreshTimer) { _ in store.refreshLog() }
    }
}
