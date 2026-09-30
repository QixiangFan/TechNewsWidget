import SwiftUI

@main
struct TechNewsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // The masthead names the window, so the title bar only keeps the toolbar.
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 800)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceOption.saved.apply()
    }

    // A single-window reader: closing the window should quit, not linger in the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
