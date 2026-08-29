import SwiftUI
import AppKit

struct TaskDetailView: View {
    private enum Tab: String, CaseIterable, Identifiable, Hashable {
        case sources = "Sources"
        case destination = "Destination"
        case schedule = "Schedule"
        var id: String { rawValue }
    }

    let taskID: UUID
    @EnvironmentObject private var store: BackupStore
    @EnvironmentObject private var progressTracker: SyncProgressTracker
    @State private var tab: Tab = .sources
    @State private var showRemoveConfirm = false
    @FocusState private var nameFieldFocused: Bool

    private var task: SyncTask? { store.tasks.first(where: { $0.id == taskID }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField(
                    "Task name",
                    text: Binding(
                        get: { task?.name ?? "" },
                        set: { store.renameTask(taskID, to: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .foregroundStyle(Theme.highlight2)
                .focused($nameFieldFocused)
                .onChange(of: nameFieldFocused) { focused in
                    if !focused { store.assignDefaultNameIfEmpty(taskID) }
                }
                .onChange(of: store.pendingRenameTaskID) { pending in
                    guard pending == taskID else { return }
                    nameFieldFocused = true
                    store.pendingRenameTaskID = nil
                }
                .onAppear {
                    guard store.pendingRenameTaskID == taskID else { return }
                    nameFieldFocused = true
                    store.pendingRenameTaskID = nil
                }

                Spacer()

                HStack(spacing: 4) {
                    VStack(spacing: 4) {
                        ChromeIconButton(systemImage: "pencil") {
                            nameFieldFocused = true
                        }
                        Text("Rename")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.gray2)
                    }
                    .frame(width: 68)
                    .help("Rename this sync task")

                    VStack(spacing: 4) {
                        RunTaskButton(taskID: taskID)
                        Text("Sync Task")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.gray2)
                    }
                    .frame(width: 68)

                    if store.runStatus(for: taskID) == .running {
                        VStack(spacing: 4) {
                            ChromeIconButton(systemImage: store.isTaskPaused(taskID) ? "play.fill" : "pause.fill") {
                                store.togglePauseTask(taskID)
                            }
                            .disabled(store.isTaskPausing(taskID) || store.isTaskStopping(taskID))
                            Text("Pause")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.gray2)
                        }
                        .frame(width: 68)
                        .help(store.isTaskPaused(taskID) ? "Resume this backup" : "Pause this backup")

                        VStack(spacing: 4) {
                            ChromeIconButton(systemImage: "stop.fill") {
                                store.stopTask(taskID)
                            }
                            .disabled(store.isTaskStopping(taskID))
                            Text("Stop")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.gray2)
                        }
                        .frame(width: 68)
                        .help("Stop this backup")
                    }

                    VStack(spacing: 4) {
                        ChromeIconButton(systemImage: "trash") {
                            showRemoveConfirm = true
                        }
                        Text("Delete Task")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.gray2)
                    }
                    .frame(width: 68)
                    .help("Delete this sync task")
                }
            }

            if store.runStatus(for: taskID) == .running {
                if let statusLine {
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                }
                progressSection
            } else if let summary = store.lastRunSummaries[taskID] {
                CompletionBanner(
                    summary: summary,
                    onViewLog: { NSWorkspace.shared.activateFileViewerSelecting([ConfigIO.logFile]) },
                    onDismiss: { store.dismissRunSummary(taskID) }
                )
            }

            if let reasons = store.taskFailureReasons[taskID], !reasons.isEmpty {
                failureReasonSection(reasons)
            }

            summaryCardsRow

            ChromeSegmentedControl(tabs: Tab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                .frame(maxWidth: 420, alignment: .leading)

            // Only this tab body scrolls — the name/buttons, status, and
            // summary cards above stay pinned so a short window never has to
            // be scrolled just to see the task's name or run its controls.
            ScrollView {
                switch tab {
                case .sources: TaskSourcesView(taskID: taskID)
                case .destination: TaskDestinationView(taskID: taskID)
                case .schedule: TaskScheduleView(taskID: taskID)
                }
            }
        }
        .confirmationDialog(
            "Delete “\(task?.name ?? "this task")”?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { store.removeTask(taskID) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes its schedule too. Files already backed up are not deleted.")
        }
    }

    private var statusLine: String? {
        switch store.runStatus(for: taskID) {
        case .idle:
            return nil
        case .running:
            if store.isTaskStopping(taskID) { return "Stopping…" }
            if store.isTaskPausing(taskID) { return "Pausing…" }
            return store.isTaskPaused(taskID) ? "Paused" : "Syncing…"
        case .succeeded(let date):
            return "Completed at \(Self.timeFormatter.string(from: date))"
        case .failed(let date):
            return "Failed at \(Self.timeFormatter.string(from: date))"
        case .stopped(let date):
            return "Stopped at \(Self.timeFormatter.string(from: date))"
        }
    }

    private var statusColor: Color {
        switch store.runStatus(for: taskID) {
        case .idle, .running: return Theme.gray2
        case .succeeded: return .green
        case .failed: return .red
        case .stopped: return .orange
        }
    }

    private func failureReasonSection(_ reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Why it failed")
                .font(.caption.bold())
                .foregroundStyle(Theme.gray1)
            ForEach(reasons, id: \.self) { reason in
                Text(cleanedFailureReason(reason))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.charcoalDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Strips rsync's "rsync(12345): " process-id prefix for readability.
    private func cleanedFailureReason(_ line: String) -> String {
        guard let range = line.range(of: #"^rsync\(\d+\):\s*"#, options: .regularExpression) else { return line }
        return String(line[range.upperBound...])
    }

    /// A Source/Destination/Schedule summary row, styled after Carbon Copy
    /// Cloner's task cards, so the whole config is visible at a glance —
    /// tapping a card jumps to that tab below for editing.
    private var summaryCardsRow: some View {
        HStack(spacing: 10) {
            SummaryCard(icon: "folder.fill", title: "Sources", detail: sourcesSummaryText) {
                tab = .sources
                if task?.sources.isEmpty ?? true {
                    chooseSourceDirectories()
                }
            }
            SummaryCard(icon: "externaldrive.fill", title: "Destination", detail: destinationSummaryText, detailColor: destinationSummaryColor) {
                tab = .destination
                if task?.destination?.isEmpty ?? true {
                    chooseDestination()
                }
            }
            SummaryCard(icon: "clock.fill", title: "Schedule", detail: task?.schedule.summary ?? "Off") {
                tab = .schedule
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func chooseSourceDirectories() {
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

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the backup destination root"
        if panel.runModal() == .OK, let url = panel.url {
            store.setDestination(url.path, for: taskID)
        }
    }

    private var sourcesSummaryText: String {
        guard let sources = task?.sources, !sources.isEmpty else { return "No directories yet" }
        if sources.count == 1 { return sources[0].path }
        return "\(sources.count) directories"
    }

    private var destinationSummaryText: String {
        guard let destination = task?.destination, !destination.isEmpty else { return "Not set" }
        return store.isDestinationReachable(taskID) ? destination : "Not reachable"
    }

    private var destinationSummaryColor: Color {
        guard let destination = task?.destination, !destination.isEmpty else { return Theme.gray2 }
        return store.isDestinationReachable(taskID) ? Theme.gray2 : .red
    }

    @ViewBuilder
    private var progressSection: some View {
        if let progress = progressTracker.progress(for: taskID) {
            VStack(alignment: .leading, spacing: 5) {
                ChromeProgressBar(fraction: progress.fraction, tint: store.isTaskPaused(taskID) ? Theme.gray2 : Theme.highlight2)
                HStack {
                    Text(progressDetailText(progress))
                    Spacer()
                    if let eta = progress.etaSeconds, !store.isTaskPaused(taskID) {
                        Text("ETA \(Self.etaString(eta))")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.gray2)
            }
            .frame(maxWidth: 420)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Calculating sync size…").foregroundStyle(Theme.gray2)
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private func progressDetailText(_ progress: RsyncRunner.SyncProgress) -> String {
        let done = Self.byteFormatter.string(fromByteCount: progress.bytesDone)
        let total = Self.byteFormatter.string(fromByteCount: progress.bytesTotal)
        var text = "\(done) of \(total)"
        if progress.sourceCount > 1 {
            text += " · Source \(progress.sourceIndex) of \(progress.sourceCount)"
        }
        return text
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func etaString(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
