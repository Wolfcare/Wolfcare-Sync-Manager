import SwiftUI
import AppKit

struct TaskSourcesView: View {
    let taskID: UUID
    @EnvironmentObject private var store: BackupStore
    // Deliberately never started: this icon is a purely decorative background
    // watermark, and animating it here duplicated the cost of the main
    // window's/menu bar's own spinning icon at the exact moment a user
    // switches into this tab during a run — noticeable on slower Macs. A
    // rotation object that never starts renders the same still icon at zero
    // ongoing cost.
    @StateObject private var watermarkRotation = SquaresRotation()

    private var sources: [SourceEntry] {
        store.tasks.first(where: { $0.id == taskID })?.sources ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Kept above the (potentially long) source list so they're
            // visible without scrolling — the count/Add button in particular
            // is the main action on this tab, not something to hunt for.
            if !sources.isEmpty {
                HStack {
                    Button {
                        chooseDirectories()
                    } label: {
                        Label("Add Directory…", systemImage: "plus")
                    }
                    .buttonStyle(.chrome)
                    Spacer()
                    Text("\(sources.count) director\(sources.count == 1 ? "y" : "ies")")
                        .foregroundStyle(Theme.gray2)
                }

                Text("Contents Only copies what's inside the folder straight into the destination. Folder + Contents copies the folder itself as a subfolder there, so sources with same-named files don't collide.")
                    .font(.footnote)
                    .foregroundStyle(Theme.gray2)
            }

            Group {
                if sources.isEmpty {
                    VStack(spacing: 14) {
                        ContentUnavailableViewCompat(
                            title: "No directories configured yet",
                            message: "Add a folder to include it in this task's backups.",
                            systemImage: "folder.badge.plus"
                        )
                        Button {
                            chooseDirectories()
                        } label: {
                            Label("Add Directory…", systemImage: "plus")
                        }
                        .buttonStyle(.chrome)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    List {
                        ForEach(sources) { entry in
                            HStack {
                                Button {
                                    changeSource(entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Image(systemName: "folder")
                                                .font(.system(size: 13 * 1.2))
                                            Text(entry.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .foregroundStyle(Theme.highlight1)
                                        Text("Click folder icon to change source")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.gray2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Change this source's folder")
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
                    .scrollContentBackground(.hidden)
                    .listStyle(.inset)
                    .frame(minHeight: 200)
                }
            }
            .background {
                ImitorIconView(rotation: watermarkRotation)
                    .opacity(0.08)
                    .allowsHitTesting(false)
            }
        }
    }

    private func changeSource(_ entry: SourceEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Change"
        panel.message = "Choose a new folder for this source"
        panel.directoryURL = URL(fileURLWithPath: entry.path)
        if panel.runModal() == .OK, let url = panel.url {
            store.replaceSourcePath(entry.id, in: taskID, with: url.path)
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
                .foregroundStyle(Theme.gray2)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.highlight1)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.gray2)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .multilineTextAlignment(.center)
    }
}
