import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar after the main window is closed — this
        // is what lets scheduled tasks keep firing and stay checkable from the
        // menu bar without the window open. Also drop the Dock icon/Cmd+Tab
        // entry at the same time, so "closed" actually behaves like closed
        // rather than a windowless app still sitting in the Dock. The menu
        // bar's "Open Imitor Sync Manager…" item restores .regular when it
        // reopens the window.
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
