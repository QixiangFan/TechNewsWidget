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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // A single-window reader: closing the window should quit, not linger in the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
