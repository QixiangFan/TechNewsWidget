import Foundation
import NewsKit
import Security

/// The App Group the app and the widget share (see the `.entitlements` files). Settings live in its
/// defaults and the widget's cache in its container, so the app can show and clear what the widget keeps.
nonisolated enum AppGroup {
    /// "<Team ID>.com.qixiangfan.TechNews", read from this process's own entitlements so the Team ID
    /// is written down in one place only. Nil in unsigned builds, which then keep everything to themselves.
    static let identifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
                as? [String] else {
            return nil
        }
        return groups.first
    }()

    static let defaults = identifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    /// `<group container>/Library/Caches/TechNews`.
    static let cacheDirectory = identifier
        .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        .map { $0.appendingPathComponent("Library/Caches/TechNews", isDirectory: true) }
        ?? NewsCache.defaultDirectory
}

extension NewsCache {
    /// The headlines the widget keeps, in the App Group.
    nonisolated static let shared = NewsCache(directory: AppGroup.cacheDirectory)
}

extension ThumbnailStore {
    /// The widget's thumbnails, in a folder inside `NewsCache.shared`'s.
    nonisolated static let shared = ThumbnailStore(
        directory: AppGroup.cacheDirectory.appendingPathComponent("thumbs", isDirectory: true))
}
