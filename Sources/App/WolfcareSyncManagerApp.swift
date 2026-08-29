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
                .environmentObject(store.progressTracker)
                // The chrome-on-charcoal look uses fixed colors, not adaptive
                // ones — it's a deliberate brand identity, not meant to follow
                // system appearance. Without this, native controls (toolbar,
                // window chrome, default buttons/pickers) still follow the
                // system's actual Light/Dark setting, clashing badly with the
                // fixed-dark custom views on a Mac set to Light Mode.
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(store.progressTracker)
                .preferredColorScheme(.dark)
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
        case .stopped: return .orange
        case .idle, .succeeded: return nil
        }
    }
}
