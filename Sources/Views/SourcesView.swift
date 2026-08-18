import SwiftUI
import AppKit

struct TaskSourcesView: View {
    let taskID: UUID
    @EnvironmentObject private var store: BackupStore

    private var sources: [SourceEntry] {
        store.tasks.first(where: { $0.id == taskID })?.sources ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sources.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No directories configured yet",
                    message: "Add a folder to include it in this task's backups.",
                    systemImage: "folder.badge.plus"
                )
            } else {
                List {
                    ForEach(sources) { entry in
                        HStack {
                            Label(entry.path, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { entry.copyMode },
                                set: { store.setCopyMode($0, forSource: entry.id, in: taskID) }
                            )) {
                                Text("Contents Only").tag(CopyMode.contentsOnly)
                                Text("Folder + Contents").tag(CopyMode.folderAndContents)
                            }
                            .labelsHidden()
                            .frame(width: 190)
                        }
                    }
                    .onDelete { offsets in
                        store.removeSources(at: offsets, from: taskID)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)

                Text("Contents Only copies what's inside the folder straight into the destination. Folder + Contents copies the folder itself as a subfolder there, so sources with same-named files don't collide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    chooseDirectories()
                } label: {
                    Label("Add Directory…", systemImage: "plus")
                }
                Spacer()
                Text("\(sources.count) director\(sources.count == 1 ? "y" : "ies")")
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
                store.addSource(url.path, to: taskID)
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
