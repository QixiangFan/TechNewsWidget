import Foundation
import WidgetKit

/// Tells the widgets about changes made in the app.
enum WidgetReloader {
    private static var pendingReload: Task<Void, Never>?

    /// Reloads the widgets a moment after a setting changes, once for a burst of changes
    /// such as several sources turned off in a row.
    static func reloadSoon() {
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Makes every widget download fresh headlines now, even if it downloaded a minute ago.
    static func refreshNow() {
        AppGroup.defaults.set(Date(), forKey: NewsSettings.Key.refreshRequestedAt)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
