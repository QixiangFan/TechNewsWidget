import Foundation
import NewsKit
import WidgetKit

struct NewsEntry: TimelineEntry {
    let date: Date
    let category: NewsCategory
    /// Headlines on the current page only.
    let items: [NewsItem]
    /// When the headlines were downloaded; nil when nothing could be loaded.
    let fetchedAt: Date?
    let page: Int
    let pageCount: Int
    /// Sample content (widget gallery), drawn redacted.
    var isPlaceholder = false
}

/// Supplies the widget's content. Downloads happen here, inside the sandboxed widget
/// extension; the last good result is kept in the small `NewsCache`.
struct NewsProvider: AppIntentTimelineProvider {
    /// How long a download stays current before the widget asks for a new one.
    static let refreshInterval: TimeInterval = 2 * 60 * 60
    /// Retry delay after a download failed completely.
    static let retryInterval: TimeInterval = 15 * 60
    /// Reloads within this window reuse the cache instead of downloading again,
    /// e.g. when several widgets reload at the same time.
    static let minimumFetchInterval: TimeInterval = 5 * 60

    private let service = NewsService()
    private let cache = NewsCache()

    func placeholder(in context: Context) -> NewsEntry {
        .sample(for: .all, family: context.family)
    }

    func snapshot(for configuration: SelectCategoryIntent, in context: Context) async -> NewsEntry {
        let category = configuration.category.newsCategory
        // The widget gallery needs an instant answer: cached headlines, or a redacted sample.
        if context.isPreview {
            guard let cached = cache.load(category) else {
                return .sample(for: category, family: context.family)
            }
            return makeEntry(cached, category: category, family: context.family, date: Date())
        }
        let (news, _) = await loadNews(category)
        return makeEntry(news, category: category, family: context.family, date: Date())
    }

    func timeline(for configuration: SelectCategoryIntent, in context: Context) async -> Timeline<NewsEntry> {
        let now = Date()
        let category = configuration.category.newsCategory
        let (news, downloadFailed) = await loadNews(category, now: now)
        let entry = makeEntry(news, category: category, family: context.family, date: now)

        let nextRefresh = downloadFailed
            ? now.addingTimeInterval(Self.retryInterval)
            : max((news?.fetchedAt ?? now).addingTimeInterval(Self.refreshInterval),
                  now.addingTimeInterval(Self.minimumFetchInterval))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Returns the headlines to show, downloading them when the cache is not recent enough.
    private func loadNews(_ category: NewsCategory, now: Date = Date()) async -> (CachedNews?, downloadFailed: Bool) {
        let cached = cache.load(category, now: now)
        guard shouldDownload(category, cached: cached, now: now) else {
            return (cached, false)
        }
        let result = await service.fetch(category)
        guard !result.items.isEmpty else {
            return (cached, true)
        }
        let fresh = CachedNews(fetchedAt: now, items: result.items)
        _ = try? cache.save(fresh, for: category)
        PageStore.reset(category)
        return (fresh, false)
    }

    /// Button taps and bursts of reloads reuse the cache; everything else downloads.
    private func shouldDownload(_ category: NewsCategory, cached: CachedNews?, now: Date) -> Bool {
        let reuseCache = PageStore.consumeReuseCache(for: category)
        guard let cached else { return true }
        if reuseCache { return false }
        return now.timeIntervalSince(cached.fetchedAt) >= Self.minimumFetchInterval
    }

    private func makeEntry(_ news: CachedNews?, category: NewsCategory, family: WidgetFamily, date: Date) -> NewsEntry {
        let items = news?.items ?? []
        let perPage = family.headlinesPerPage
        let pageCount = max(1, (items.count + perPage - 1) / perPage)
        let page = PageStore.page(for: category) % pageCount
        return NewsEntry(
            date: date,
            category: category,
            items: Array(items.dropFirst(page * perPage).prefix(perPage)),
            fetchedAt: news?.fetchedAt,
            page: page,
            pageCount: pageCount
        )
    }
}

extension WidgetFamily {
    /// Headlines that fit on one page of each widget size.
    var headlinesPerPage: Int {
        switch self {
        case .systemSmall: 3
        case .systemMedium: 5
        case .systemLarge: 8
        case .systemExtraLarge: 16
        default: 5
        }
    }
}

/// Remembers the "next page" position per category, in the widget extension's own defaults.
enum PageStore {
    private static let defaults = UserDefaults.standard

    static func page(for category: NewsCategory) -> Int {
        defaults.integer(forKey: pageKey(category))
    }

    static func advance(_ category: NewsCategory) {
        defaults.set(page(for: category) + 1, forKey: pageKey(category))
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
    static func sample(for category: NewsCategory, family: WidgetFamily, redacted: Bool = true) -> NewsEntry {
        let sources = NewsSource.sources(for: category)
        let items = (0..<family.headlinesPerPage).map { index in
            let source = sources[index % sources.count]
            return NewsItem(
                title: index.isMultiple(of: 2)
                    ? "Sample headline used to preview the widget layout"
                    : "示例标题：用于预览小组件排版效果的一条比较长的中文标题",
                url: URL(string: "https://example.com/\(index)")!,
                sourceID: source.id,
                detail: source.kind == .feed ? nil : "+1,234★ · Swift · Sample description"
            )
        }
        return NewsEntry(
            date: Date(),
            category: category,
            items: items,
            fetchedAt: Date(),
            page: 0,
            pageCount: 3,
            isPlaceholder: redacted
        )
    }
}
