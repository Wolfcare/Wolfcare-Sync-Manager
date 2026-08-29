import SwiftUI

struct TaskDetailView: View {
    private enum Tab: String, CaseIterable, Identifiable {
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

                Spacer()

                RunTaskButton(taskID: taskID)

                if store.runStatus(for: taskID) == .running {
                    Button {
                        store.togglePauseTask(taskID)
                    } label: {
                        Image(systemName: store.isTaskPaused(taskID) ? "play.circle.fill" : "pause.circle.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 30))
                    .help(store.isTaskPaused(taskID) ? "Resume this backup" : "Pause this backup")

                    Button {
                        store.stopTask(taskID)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 30))
                    .help("Stop this backup")
                }

                Button {
                    showRemoveConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .font(.system(size: 26))
                .help("Delete this sync task")
            }

            if let statusLine {
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            if store.runStatus(for: taskID) == .running {
                progressSection
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            switch tab {
            case .sources: TaskSourcesView(taskID: taskID)
            case .destination: TaskDestinationView(taskID: taskID)
            case .schedule: TaskScheduleView(taskID: taskID)
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
        case .idle, .running: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        case .stopped: return .orange
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let progress = progressTracker.progress(for: taskID) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.fraction)
                    .tint(store.isTaskPaused(taskID) ? .yellow : .accentColor)
                HStack {
                    Text(progressDetailText(progress))
                    Spacer()
                    if let eta = progress.etaSeconds, !store.isTaskPaused(taskID) {
                        Text("ETA \(Self.etaString(eta))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
        } else {
            ProgressView("Calculating sync size…")
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
