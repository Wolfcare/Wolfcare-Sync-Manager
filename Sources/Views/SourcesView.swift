import SwiftUI
import AppKit

struct SourcesView: View {
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Directories to back up")
                .font(.title2.bold())

            if store.sources.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No directories configured yet",
                    message: "Add a folder to include it in every backup run.",
                    systemImage: "folder.badge.plus"
                )
            } else {
                List {
                    ForEach(store.sources, id: \.self) { path in
                        Label(path, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onDelete { offsets in
                        store.removeSources(at: offsets)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)
            }

            HStack {
                Button {
                    chooseDirectories()
                } label: {
                    Label("Add Directory…", systemImage: "plus")
                }
                Spacer()
                Text("\(store.sources.count) director\(store.sources.count == 1 ? "y" : "ies")")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more directories to back up"
        if panel.runModal() == .OK {
            for url in panel.urls {
                store.addSource(url.path)
            }
        }
    }
}

/// Minimal stand-in for ContentUnavailableView (macOS 14+) so this stays
/// compatible with the macOS 13 deployment target.
struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .multilineTextAlignment(.center)
    }
}
