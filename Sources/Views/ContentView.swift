import SwiftUI

struct ContentView: View {
    enum Selection: Hashable {
        case task(UUID)
        case activityLog
    }

    @EnvironmentObject private var store: BackupStore
    @State private var selection: Selection?
    @State private var renamingTaskID: UUID?
    @State private var renameDraft: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Sync Tasks") {
                    ForEach(store.tasks) { task in
                        taskRow(task)
                            .tag(Selection.task(task.id))
                    }
                    if store.tasks.isEmpty {
                        Text("No tasks yet").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Activity Log", systemImage: "doc.text")
                        .tag(Selection.activityLog)
                }
            }
            .navigationTitle("Wolfcare Sync Manager")
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        let id = store.addTask()
                        selection = .task(id)
                    } label: {
                        Label("Add Sync Task", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Group {
                switch selection {
                case .task(let id) where store.tasks.contains(where: { $0.id == id }):
                    TaskDetailView(taskID: id)
                case .activityLog:
                    LogView()
                default:
                    Text("Select a sync task, or add one with the + button")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            if selection == nil {
                selection = store.tasks.first.map { .task($0.id) } ?? .activityLog
            }
        }
        .onChange(of: store.tasks.map(\.id)) { ids in
            if case .task(let id) = selection, !ids.contains(id) {
                selection = ids.first.map { .task($0) } ?? .activityLog
            }
        }
        .alert("Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func statusIcon(for taskID: UUID) -> String {
        switch store.runStatus(for: taskID) {
        case .idle: return "arrow.triangle.2.circlepath"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private func taskRow(_ task: SyncTask) -> some View {
        if renamingTaskID == task.id {
            TextField("Task name", text: $renameDraft)
                .focused($renameFieldFocused)
                .onSubmit { commitRename(task.id) }
                .onExitCommand { renamingTaskID = nil }
                .onAppear { renameFieldFocused = true }
                .onChange(of: renameFieldFocused) { focused in
                    if !focused { commitRename(task.id) }
                }
        } else {
            Label(task.name, systemImage: statusIcon(for: task.id))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    selection = .task(task.id)
                    renameDraft = task.name
                    renamingTaskID = task.id
                }
        }
    }

    private func commitRename(_ taskID: UUID) {
        guard renamingTaskID == taskID else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameTask(taskID, to: trimmed)
        }
        renamingTaskID = nil
    }
}
