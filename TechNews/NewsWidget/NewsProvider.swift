import Foundation
import NewsKit
import WidgetKit

struct NewsEntry: TimelineEntry {
    let date: Date
    let category: NewsCategory
    let style: StyleOption
    /// Headlines on the current page only.
    let items: [NewsItem]
    /// Positions in a ranked category (Hacker News), keyed by `NewsItem.id`. Counted before muted
    /// words hide any stories, so every story keeps its rank on the site.
    var ranks: [String: Int] = [:]
    /// JPEG thumbnails of `items`, keyed by `NewsItem.id` (rich style only).
    var thumbnails: [String: Data] = [:]
    /// When the headlines were downloaded; nil when nothing could be loaded.
    let fetchedAt: Date?
    /// Pages turned forward minus pages turned back since the headlines arrived, so it can pass
    /// either end. `page` is this wrapped into `0..<pageCount`; the view slides by `position`
    /// (see `PageStrip`), which keeps a turn that wraps around moving in the button's direction.
    let position: Int
    let page: Int
    let pageCount: Int
    /// Sample content (widget gallery), drawn redacted.
    var isPlaceholder = false
    /// Every source of the category is turned off in the app's settings.
    var sourcesOff = false
}

/// Supplies the widget's content. Downloads happen here, inside the sandboxed widget
/// extension; the last good result is kept in the small `NewsCache`, and the pictures
/// of the page on screen in `ThumbnailStore`, both in the App Group so the app can clear them.
/// How often to download, which sources to use and which words to hide come from `NewsSettings`.
struct NewsProvider: AppIntentTimelineProvider {
    /// Retry delay after a download failed completely.
    static let retryInterval: TimeInterval = 15 * 60
    /// Reloads within this window reuse the cache instead of downloading again,
    /// e.g. when several widgets reload at the same time.
    static let minimumFetchInterval: TimeInterval = 5 * 60

    private let service = NewsService()
    private let cache = NewsCache.shared
    private let thumbnailStore = ThumbnailStore.shared

    func placeholder(in context: Context) -> NewsEntry {
        .sample(for: .all, style: .rich, family: context.family)
    }

    func snapshot(for configuration: SelectCategoryIntent, in context: Context) async -> NewsEntry {
        let category = configuration.category.newsCategory
        let style = configuration.style
        let settings = NewsSettings.load()
        // The widget gallery needs an instant answer: cached headlines and pictures, or a redacted sample.
        if context.isPreview {
            guard let cached = cache.load(category) else {
                return .sample(for: category, style: style, family: context.family)
            }
            var entry = makeEntry(cached, category: category, style: style, settings: settings, family: context.family,
                                  date: Date())
            if style == .rich {
                entry.thumbnails = thumbnailStore.cachedThumbnails(
                    for: entry.items, leadItemIDs: Self.leadItemIDs(of: entry, family: context.family))
            }
            return entry
        }
        let (news, _) = await loadNews(category, settings: settings)
        let entry = makeEntry(news, category: category, style: style, settings: settings, family: context.family,
                              date: Date())
        return await withThumbnails(entry, family: context.family)
    }

    func timeline(for configuration: SelectCategoryIntent, in context: Context) async -> Timeline<NewsEntry> {
        let now = Date()
        let category = configuration.category.newsCategory
        let settings = NewsSettings.load()
        let (news, downloadFailed) = await loadNews(category, settings: settings, now: now)
        let entry = await withThumbnails(
            makeEntry(news, category: category, style: configuration.style, settings: settings, family: context.family,
                      date: now),
            family: context.family)

        let nextRefresh = downloadFailed
            ? now.addingTimeInterval(Self.retryInterval)
            : max((news?.fetchedAt ?? now).addingTimeInterval(settings.refreshInterval.seconds),
                  now.addingTimeInterval(Self.minimumFetchInterval))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Returns the headlines to show, downloading them from the sources that are turned on when the
    /// cache is not recent enough.
    private func loadNews(_ category: NewsCategory, settings: NewsSettings,
                          now: Date = Date()) async -> (CachedNews?, downloadFailed: Bool) {
        removeCacheOutsideAppGroup()
        cache.removeExpired(now: now)
        thumbnailStore.removeExpired(now: now)
        let reuseCache = PageStore.consumeReuseCache(for: category)
        let cached = cache.load(category, now: now)
        let sources = settings.sources(for: category)
        guard !sources.isEmpty,
              shouldDownload(cached: cached, sources: sources, reuseCache: reuseCache, settings: settings, now: now) else {
            return (cached, false)
        }
        let result = await service.fetch(sources)
        guard !result.items.isEmpty else {
            return (cached, true)
        }
        let fresh = CachedNews(fetchedAt: now, items: result.items, sourceIDs: sources.map(\.id),
                               topStoryIDs: result.topStoryIDs)
        _ = try? cache.save(fresh, for: category)
        PageStore.reset(category)
        return (fresh, false)
    }

    /// Button taps reuse the cache. Otherwise the widget downloads when sources were turned on or off,
    /// when the app asked for fresh headlines, or when the cache is more than a few minutes old
    /// (so bursts of reloads download once).
    private func shouldDownload(cached: CachedNews?, sources: [NewsSource], reuseCache: Bool,
                                settings: NewsSettings, now: Date) -> Bool {
        guard let cached else { return true }
        if reuseCache { return false }
        if cached.sourceIDs != sources.map(\.id) { return true }
        if let requested = settings.refreshRequestedAt, cached.fetchedAt < requested { return true }
        return now.timeIntervalSince(cached.fetchedAt) >= Self.minimumFetchInterval
    }

    /// Before the App Group, the widget kept its cache in its own container; that copy is no longer read.
    private func removeCacheOutsideAppGroup() {
        guard AppGroup.cacheDirectory != NewsCache.defaultDirectory else { return }
        NewsCache().removeAll()
    }

    /// The current page of the stories the settings let through, in the order they ask for. Until a download with the current
    /// sources succeeds, the cache may still hold stories from a source that was just turned off.
    private func makeEntry(_ news: CachedNews?, category: NewsCategory, style: StyleOption, settings: NewsSettings,
                           family: WidgetFamily, date: Date) -> NewsEntry {
        let allItems = news?.items ?? []
        let items = settings.storyOrder.arrange(allItems, topStoryIDs: news?.topStoryIDs).filter(settings.shows)
        let perPage = family.headlinesPerPage(style: style)
        let pageCount = max(1, (items.count + perPage - 1) / perPage)
        let position = PageStore.position(for: category)
        // Wraps in both directions: position -1 is the last page.
        let page = (position % pageCount + pageCount) % pageCount
        let pageItems = Array(items.dropFirst(page * perPage).prefix(perPage))
        return NewsEntry(
            date: date,
            category: category,
            style: style,
            items: pageItems,
            ranks: category.showsRanks ? Self.ranks(of: pageItems, in: allItems) : [:],
            fetchedAt: news?.fetchedAt,
            position: position,
            page: page,
            pageCount: pageCount,
            sourcesOff: settings.sources(for: category).isEmpty
        )
    }

    /// Each story's position in the whole list, starting at 1.
    private static func ranks(of items: [NewsItem], in allItems: [NewsItem]) -> [String: Int] {
        let ids = Set(items.map(\.id))
        var ranks: [String: Int] = [:]
        for (index, item) in allItems.enumerated() where ids.contains(item.id) {
            ranks[item.id] = index + 1
        }
        return ranks
    }

    /// Adds the pictures of the rich style, downloading the ones not on disk yet.
    private func withThumbnails(_ entry: NewsEntry, family: WidgetFamily) async -> NewsEntry {
        guard entry.style == .rich else { return entry }
        var entry = entry
        entry.thumbnails = await thumbnailStore.thumbnails(
            for: entry.items, leadItemIDs: Self.leadItemIDs(of: entry, family: family))
        return entry
    }

    /// The large sizes open with a wide lead picture, which needs a sharper copy.
    private static func leadItemIDs(of entry: NewsEntry, family: WidgetFamily) -> Set<String> {
        guard family == .systemLarge || family == .systemExtraLarge, let lead = entry.items.first else { return [] }
        return [lead.id]
    }
}

extension WidgetFamily {
    /// Stories that fit on one page of each widget size (see `RichLayout` and `CompactLayout`).
    func headlinesPerPage(style: StyleOption) -> Int {
        switch (style, self) {
        case (.rich, .systemSmall): 1
        case (.rich, .systemMedium): 2
        case (.rich, .systemLarge): 4
        case (.rich, .systemExtraLarge): 5
        case (.headlines, .systemSmall): 3
        case (.headlines, .systemMedium): 6
        case (.headlines, .systemLarge): 8
        case (.headlines, .systemExtraLarge): 16
        default: 5
        }
    }
}

/// Remembers the page position per category, in the widget extension's own defaults.
/// Widgets of different sizes share it and each wraps it into its own page count.
enum PageStore {
    private static let defaults = UserDefaults.standard

    static func position(for category: NewsCategory) -> Int {
        defaults.integer(forKey: pageKey(category))
    }

    /// Moves `pages` forward, or back when negative.
    static func turn(_ category: NewsCategory, by pages: Int) {
        defaults.set(position(for: category) + pages, forKey: pageKey(category))
        reuseCacheOnce(category)
    }

    /// Makes the next reload show cached headlines instead of downloading, so a button
    /// tap never replaces the list (and resets the page) under the user's cursor.
    static func reuseCacheOnce(_ category: NewsCategory) {
        defaults.set(true, forKey: reuseKey(category))
    }

    /// True once after `reuseCacheOnce`.
    static func consumeReuseCache(for category: NewsCategory) -> Bool {
        let reuse = defaults.bool(forKey: reuseKey(category))
        if reuse {
            defaults.removeObject(forKey: reuseKey(category))
        }
        return reuse
    }

    /// Back to the first page, used after new headlines arrive.
    static func reset(_ category: NewsCategory) {
        defaults.removeObject(forKey: pageKey(category))
    }

    private static func pageKey(_ category: NewsCategory) -> String { "page.\(category.rawValue)" }
    private static func reuseKey(_ category: NewsCategory) -> String { "reuseCache.\(category.rawValue)" }
}

extension NewsEntry {
    /// Layout-only content for placeholders, the widget gallery and Xcode previews.
    /// The titles are clearly marked as samples; they are never shown as real news.
    static func sample(for category: NewsCategory, style: StyleOption, family: WidgetFamily,
                       redacted: Bool = true) -> NewsEntry {
        let sources = NewsSource.sources(for: category)
        let items = (0..<family.headlinesPerPage(style: style)).map { index in
            let source = sources[index % sources.count]
            let english = index.isMultiple(of: 2)
            return NewsItem(
                title: english
                    ? "Sample headline used to preview the widget layout"
                    : "示例标题：用于预览小组件排版效果的一条比较长的中文标题",
                url: URL(string: "https://example.com/\(index)")!,
                sourceID: source.id,
                date: Date(),
                detail: source.kind == .feed || source.kind == .wordpress ? nil : "+1,234★ · Swift",
                summary: english
                    ? "A sample summary that shows where the outlet's own description of the story goes."
                    : "示例摘要：这里显示媒体为这篇文章写的导语，最多两行。"
            )
        }
        return NewsEntry(
            date: Date(),
            category: category,
            style: style,
            items: items,
            ranks: category.showsRanks ? Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0 + 1) }) : [:],
            fetchedAt: Date(),
            position: 0,
            page: 0,
            pageCount: 3,
            isPlaceholder: redacted
        )
    }
}
