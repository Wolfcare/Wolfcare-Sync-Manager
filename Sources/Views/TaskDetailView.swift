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

                Button {
                    showRemoveConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this sync task")
            }

            if let statusLine {
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
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
            return "Syncing…"
        case .succeeded(let date):
            return "Completed at \(Self.timeFormatter.string(from: date))"
        case .failed(let date):
            return "Failed at \(Self.timeFormatter.string(from: date))"
        }
    }

    private var statusColor: Color {
        switch store.runStatus(for: taskID) {
        case .idle, .running: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
