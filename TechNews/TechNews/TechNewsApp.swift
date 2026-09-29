import SwiftUI

@main
struct TechNewsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // The masthead names the window, so the title bar only keeps the toolbar.
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 800)
    }
}
