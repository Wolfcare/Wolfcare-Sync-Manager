import SwiftUI

// Note: no @main here — Sources/App/main.swift decides between this
// normal GUI launch and the headless `--run` path before SwiftUI starts.
struct WolfcareSyncManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: BackupStore
    @StateObject private var menuBarIcon: MenuBarIconRenderer

    init() {
        let store = BackupStore()
        _store = StateObject(wrappedValue: store)
        _menuBarIcon = StateObject(wrappedValue: MenuBarIconRenderer(rotation: store.iconRotation))
    }

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
            Image(nsImage: menuBarIcon.image)
                .resizable()
                .frame(width: 24, height: 24)
                .overlay(alignment: .bottomTrailing) {
                    if let badgeColor {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 6, height: 6)
                    }
                }
        }
        .menuBarExtraStyle(.menu)
    }

    private var badgeColor: Color? {
        switch store.overallStatus {
        case .running: return .blue
        case .failed: return .red
        case .idle, .succeeded: return nil
        }
    }
}
