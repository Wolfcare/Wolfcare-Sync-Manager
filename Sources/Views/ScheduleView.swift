import SwiftUI

struct TaskScheduleView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case off = "Off"
        case hourly = "Every hour"
        case daily = "Daily at a time"
        case weekly = "Weekly"
        case everyN = "Every N minutes"
        case once = "Run once at"
        var id: String { rawValue }
    }

    let taskID: UUID
    @EnvironmentObject private var store: BackupStore

    @State private var kind: Kind = .off
    @State private var hour: Int = 2
    @State private var minute: Int = 0
    @State private var weekday: Int = 1 // Monday
    @State private var everyN: Int = 30
    @State private var onceDate: Date = Date().addingTimeInterval(3600)
    @State private var loadedForTaskID: UUID?

    private let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var currentSchedule: ScheduleKind {
        store.tasks.first(where: { $0.id == taskID })?.schedule ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatic Backups")
                .font(.title2.bold())
                .foregroundStyle(Theme.highlight2)

            Text("Currently: \(currentSchedule.summary)")
                .foregroundStyle(Theme.gray2)

            Picker("Run", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch kind {
            case .off, .hourly:
                EmptyView()
            case .daily:
                HStack {
                    Stepper(String(format: "Hour: %02d", hour), value: $hour, in: 0...23)
                    Stepper(String(format: "Minute: %02d", minute), value: $minute, in: 0...59, step: 5)
                }
            case .weekly:
                HStack {
                    Picker("Day", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { Text(weekdayNames[$0]).tag($0) }
                    }
                    .frame(width: 160)
                    Stepper(String(format: "Hour: %02d", hour), value: $hour, in: 0...23)
                    Stepper(String(format: "Minute: %02d", minute), value: $minute, in: 0...59, step: 5)
                }
            case .everyN:
                Stepper("Every \(everyN) minutes", value: $everyN, in: 1...1440)
            case .once:
                DatePicker("Run at", selection: $onceDate)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }

            HStack {
                Button("Apply Schedule") {
                    applySchedule()
                }
                .buttonStyle(.chrome)
                if currentSchedule != .off {
                    Button("Remove Schedule", role: .destructive) {
                        store.clearSchedule(for: taskID)
                        kind = .off
                    }
                }
            }

            Text("Backups run in the background via a launchd LaunchAgent, even when this app's window is closed, as long as you're logged in.")
                .font(.footnote)
                .foregroundStyle(Theme.gray2)

            Spacer()
        }
        .onAppear { syncFromStore() }
        .onChange(of: taskID) { _ in syncFromStore() }
    }

    private func syncFromStore() {
        guard loadedForTaskID != taskID else { return }
        loadedForTaskID = taskID
        switch currentSchedule {
        case .off:
            kind = .off
        case .hourly:
            kind = .hourly
        case .daily(let h, let m):
            kind = .daily; hour = h; minute = m
        case .weekly(let w, let h, let m):
            kind = .weekly; weekday = w; hour = h; minute = m
        case .everyNMinutes(let n):
            kind = .everyN; everyN = n
        case .once(let date):
            kind = .once; onceDate = date
        }
    }

    private func applySchedule() {
        let resolved: ScheduleKind
        switch kind {
        case .off: resolved = .off
        case .hourly: resolved = .hourly
        case .daily: resolved = .daily(hour: hour, minute: minute)
        case .weekly: resolved = .weekly(weekday: weekday, hour: hour, minute: minute)
        case .everyN: resolved = .everyNMinutes(everyN)
        case .once: resolved = .once(onceDate)
        }
        store.applySchedule(resolved, to: taskID)
    }
}
