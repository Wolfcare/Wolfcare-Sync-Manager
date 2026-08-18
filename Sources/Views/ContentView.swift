import SwiftUI

struct ContentView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case sources = "Sources"
        case destination = "Destination"
        case schedule = "Schedule"
        case log = "Log"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .sources: return "folder.badge.plus"
            case .destination: return "externaldrive"
            case .schedule: return "clock"
            case .log: return "doc.text"
            }
        }
    }

    @EnvironmentObject private var store: BackupStore
    @State private var selection: SidebarSection? = .sources

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationTitle("Wolfcare Sync Manager")
            .frame(minWidth: 180)
        } detail: {
            Group {
                switch selection {
                case .sources: SourcesView()
                case .destination: DestinationView()
                case .schedule: ScheduleView()
                case .log: LogView()
                case .none: Text("Select a section").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    RunBackupButton()
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .alert("Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
