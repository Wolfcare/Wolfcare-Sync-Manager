import SwiftUI
import AppKit

struct ContentView: View {
    enum Selection: Hashable {
        case task(UUID)
        case activityLog
    }

    @EnvironmentObject private var store: BackupStore
    @EnvironmentObject private var progressTracker: SyncProgressTracker
    @State private var selection: Selection?
    @State private var renamingTaskID: UUID?
    @State private var renameDraft: String = ""
    @FocusState private var renameFieldFocused: Bool
    @AppStorage("showWalkthroughOnLaunch") private var showWalkthroughOnLaunch: Bool = true
    @State private var showWalkthroughSheet = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                globalRunControls
                List(selection: $selection) {
                    Section {
                        ForEach(store.tasks) { task in
                            taskRow(task)
                                .listRowBackground(Color.clear)
                                .tag(Selection.task(task.id))
                        }
                        if store.tasks.isEmpty {
                            Text("No tasks yet").foregroundStyle(Theme.gray2)
                        }
                    } header: {
                        Text("SYNC TASKS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Theme.gray1)
                            .padding(.horizontal, 6)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                    }
                    Section {
                        Label("Activity Log", systemImage: "doc.text")
                            .foregroundStyle(Theme.highlight1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selection == .activityLog ? Theme.dark3 : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .listRowBackground(Color.clear)
                            .tag(Selection.activityLog)
                    }
                    if showWalkthroughOnLaunch {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("New here?")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.gray2)
                                Button {
                                    showWalkthroughSheet = true
                                } label: {
                                    Text("Click here for how to use")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.highlight2)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 8)
                                        .background(Theme.dark2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Divider().overlay(.white.opacity(0.08))

                Toggle("Show How To on Launch", isOn: $showWalkthroughOnLaunch)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .foregroundStyle(Theme.gray2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Theme.charcoalBase)
            .navigationTitle("Imitor Sync Manager")
            .frame(minWidth: 220)
        } detail: {
            Group {
                switch selection {
                case .task(let id) where store.tasks.contains(where: { $0.id == id }):
                    ScrollView {
                        TaskDetailView(taskID: id)
                    }
                case .activityLog:
                    LogView()
                default:
                    VStack(spacing: 10) {
                        ImitorIcon(isAnimating: false)
                            .frame(width: 72, height: 72)
                        Text("Select a sync task, or add one with the + button")
                            .foregroundStyle(Theme.gray2)
                        Button("How To") { showWalkthroughSheet = true }
                            .buttonStyle(.chrome)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .background(Theme.paneBackground)
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            if selection == nil {
                selection = store.tasks.first.map { .task($0.id) } ?? .activityLog
            }
            store.checkFullDiskAccess()
            store.checkForUpdatesIfDue()
            if showWalkthroughOnLaunch {
                showWalkthroughSheet = true
            }
        }
        .sheet(isPresented: $showWalkthroughSheet) {
            WalkthroughView()
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
        .alert("Full Disk Access Needed", isPresented: Binding(
            get: { store.fullDiskAccessWarning != nil },
            set: { if !$0 { store.fullDiskAccessWarning = nil } }
        )) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) { store.fullDiskAccessWarning = nil }
        } message: {
            Text((store.fullDiskAccessWarning ?? "") + "\n\nGrant Imitor Sync Manager Full Disk Access so it can reliably read and write every source, destination, and connected drive.")
        }
        .alert("Update Available", isPresented: Binding(
            get: { store.availableUpdate != nil },
            set: { if !$0 { store.availableUpdate = nil } }
        )) {
            Button("View Release") {
                if let url = store.availableUpdate?.htmlURL {
                    NSWorkspace.shared.open(url)
                }
                store.availableUpdate = nil
            }
            Button("Later", role: .cancel) { store.availableUpdate = nil }
        } message: {
            Text("Version \(store.availableUpdate?.version ?? "") is available on GitHub — you're on \(UpdateChecker.currentAppVersion).")
        }
        .alert(item: $store.manualUpdateCheckResult) { result in
            switch result {
            case .upToDate:
                return Alert(
                    title: Text("You're Up to Date"),
                    message: Text("Imitor Sync Manager \(UpdateChecker.currentAppVersion) is the latest version."),
                    dismissButton: .default(Text("OK"))
                )
            case .failed(let message):
                return Alert(
                    title: Text("Couldn't Check for Updates"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var globalRunControls: some View {
        HStack(spacing: 14) {
            transportButton(icon: "plus", caption: "Add Task", enabled: true, help: "Add a new sync task") {
                let id = store.addTask()
                selection = .task(id)
            }
            transportButton(icon: "arrow.triangle.2.circlepath", caption: "Sync All", enabled: store.canRunAnyTask, help: "Run all sync tasks now") {
                store.runAllTasksNow()
            }
            transportButton(
                icon: store.isAnyTaskPaused ? "play.fill" : "pause.fill",
                caption: "Pause",
                enabled: store.isAnyTaskRunning,
                help: store.isAnyTaskPaused ? "Resume all paused tasks" : "Pause all running tasks"
            ) {
                store.toggleGlobalPause()
            }
            transportButton(icon: "stop.fill", caption: "Stop", enabled: store.isAnyTaskRunning, help: "Stop all running tasks") {
                store.stopAllTasks()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func transportButton(icon: String, caption: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            ChromeIconButton(systemImage: icon, action: action)
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.gray2)
                // Without this, the caption is free to wrap ("Add Tas"/"k") once
                // the sidebar gets narrow, which understates this row's true
                // minimum width and lets NavigationSplitView shrink the sidebar
                // column past what the buttons actually need — breaking their
                // spacing along with it.
                .fixedSize()
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }

    /// Shown next to the task name in the sidebar while it's running, so a
    /// scheduled or manual run's progress is visible there without opening
    /// the task's detail view.
    private func sidebarStatusSuffix(for taskID: UUID) -> String {
        guard store.runStatus(for: taskID) == .running else { return "" }
        if store.isTaskStopping(taskID) { return " — Stopping…" }
        if store.isTaskPausing(taskID) { return " — Pausing…" }
        if store.isTaskPaused(taskID) { return " — Paused" }
        return progressTracker.progress(for: taskID) == nil ? " — Calculating…" : " — Running"
    }

    private func statusIcon(for taskID: UUID) -> String {
        if store.isTaskStopping(taskID) { return "stop.circle.fill" }
        if store.isTaskPausing(taskID) || store.isTaskPaused(taskID) { return "pause.circle.fill" }
        switch store.runStatus(for: taskID) {
        case .idle: return "arrow.triangle.2.circlepath"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .stopped: return "stop.circle"
        }
    }

    // NOTE: a left-click gesture directly on List row content (double-click
    // to rename, and separately drag-to-reorder via .onMove) both made
    // single-click selection unreliable — any second left-click-based
    // interaction on the same hit region has to arbitrate against the
    // List's own built-in click-to-select recognizer, and that arbitration
    // is what breaks things, regardless of which specific gesture API is
    // used. Rename and reorder now live in a right-click context menu
    // instead: a completely separate input channel (right mouse button),
    // so there's nothing for it to arbitrate against. Don't re-add a left
    // click/double-click/drag gesture directly on this row without testing
    // rapid selection-switching first — this is the third time it's broken.
    private func taskRow(_ task: SyncTask) -> some View {
        Group {
            if renamingTaskID == task.id {
                TextField("Task name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.highlight1)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(task.id) }
                    .onExitCommand { renamingTaskID = nil }
                    .onAppear { renameFieldFocused = true }
                    .onChange(of: renameFieldFocused) { focused in
                        if !focused { commitRename(task.id) }
                    }
            } else {
                Label(task.name + sidebarStatusSuffix(for: task.id), systemImage: statusIcon(for: task.id))
                    .foregroundStyle(Theme.highlight1)
                    .help(store.taskFailureReasons[task.id]?.first ?? "")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole row — including the empty stretch to the right of the
        // name — needs to be one hit-testable shape, or clicking anywhere
        // that isn't directly on the text/icon pixels fails to select the row.
        .contentShape(Rectangle())
        .background(
            selection == .task(task.id) ? Theme.dark3 : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contextMenu {
            Button("Rename") {
                renameDraft = task.name
                renamingTaskID = task.id
            }
            Divider()
            Button("Move Up") { moveTask(task.id, by: -1) }
                .disabled(!canMoveTask(task.id, by: -1))
            Button("Move Down") { moveTask(task.id, by: 1) }
                .disabled(!canMoveTask(task.id, by: 1))
        }
    }

    private func canMoveTask(_ taskID: UUID, by offset: Int) -> Bool {
        guard let index = store.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let destination = index + offset
        return destination >= 0 && destination < store.tasks.count
    }

    private func moveTask(_ taskID: UUID, by offset: Int) {
        guard let index = store.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let destination = offset < 0 ? index - 1 : index + 2
        store.moveTasks(fromOffsets: [index], toOffset: destination)
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
