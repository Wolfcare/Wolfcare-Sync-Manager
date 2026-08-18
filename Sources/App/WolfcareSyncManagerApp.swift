import SwiftUI

// Note: no @main here — Sources/App/main.swift decides between this
// normal GUI launch and the headless `--run` path before SwiftUI starts.
struct WolfcareSyncManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BackupStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIcon: String {
        switch store.runStatus {
        case .running: return "arrow.triangle.2.circlepath"
        case .failed: return "externaldrive.badge.exclamationmark"
        default: return "externaldrive.badge.checkmark"
        }
    }
}
