import Foundation
import NewsKit

/// The settings the widget follows, as chosen in the app's Settings window. They are stored in
/// `AppGroup.defaults`; the app's settings views bind to the same keys with `@AppStorage`.
nonisolated struct NewsSettings {
    enum Key {
        static let refreshInterval = "refreshInterval"
        /// IDs of the sources the widgets leave out, one per line.
        static let hiddenSources = "hiddenSources"
        /// One word per line.
        static let mutedWords = "mutedWords"
        /// Whether the most important stories come first (`StoryOrder`), in the widgets and the window.
        static let storyOrder = "storyOrder"
        /// Set by ⌘R and "Update Now": caches downloaded before this date are downloaded again.
        static let refreshRequestedAt = "refreshRequestedAt"
        /// The main window's light or dark look (app only).
        static let appearance = "appearance"
    }

    var refreshInterval: RefreshInterval
    var hiddenSourceIDs: Set<String>
    var mutedWords: [String]
    var storyOrder: StoryOrder
    var refreshRequestedAt: Date?

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> NewsSettings {
        NewsSettings(
            refreshInterval: RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .standard,
            hiddenSourceIDs: Set(lines(defaults.string(forKey: Key.hiddenSources) ?? "")),
            mutedWords: lines(defaults.string(forKey: Key.mutedWords) ?? ""),
            storyOrder: defaults.string(forKey: Key.storyOrder).flatMap(StoryOrder.init) ?? .standard,
            refreshRequestedAt: defaults.object(forKey: Key.refreshRequestedAt) as? Date
        )
    }

    /// The sources of `category` that are turned on, in their usual order.
    func sources(for category: NewsCategory) -> [NewsSource] {
        NewsSource.sources(for: category).filter { !hiddenSourceIDs.contains($0.id) }
    }

    /// False for stories from a hidden source or mentioning a muted word.
    func shows(_ item: NewsItem) -> Bool {
        !hiddenSourceIDs.contains(item.sourceID) && !item.mentions(anyOf: mutedWords)
    }

    /// Lists are stored as one string with a line per entry, which `@AppStorage` can bind to.
    static func lines(_ stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init)
    }
}

/// How stories of several sources are ordered.
nonisolated enum StoryOrder: String, CaseIterable, Identifiable {
    /// Stories that several outlets report come first (see `TopStories`), the rest take turns by source.
    case topStoriesFirst
    /// One story from each source in turn.
    case bySource

    static let standard = StoryOrder.topStoriesFirst

    var id: String { rawValue }

    /// `items` in this order, given the top stories picked when they were downloaded.
    func arrange(_ items: [NewsItem], topStoryIDs: [String]?) -> [NewsItem] {
        switch self {
        case .topStoriesFirst: TopStories.movedToFront(items, ids: topStoryIDs ?? [])
        case .bySource: items
        }
    }
}

/// How often headlines are downloaded again, in minutes.
nonisolated enum RefreshInterval: Int, CaseIterable, Identifiable {
    case halfHour = 30
    case hour = 60
    case twoHours = 120
    case fourHours = 240
    case eightHours = 480

    static let standard = RefreshInterval.twoHours

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}
