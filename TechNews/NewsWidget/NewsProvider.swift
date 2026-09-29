import Foundation
import NewsKit
import WidgetKit

struct NewsEntry: TimelineEntry {
    let date: Date
    let category: NewsCategory
    let style: StyleOption
    /// Headlines on the current page only.
    let items: [NewsItem]
    /// JPEG thumbnails of `items`, keyed by `NewsItem.id` (rich style only).
    var thumbnails: [String: Data] = [:]
    /// When the headlines were downloaded; nil when nothing could be loaded.
    let fetchedAt: Date?
    let page: Int
    let pageCount: Int
    /// Sample content (widget gallery), drawn redacted.
    var isPlaceholder = false
}

/// Supplies the widget's content. Downloads happen here, inside the sandboxed widget
/// extension; the last good result is kept in the small `NewsCache`, and the pictures
/// of the page on screen in `ThumbnailStore`.
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
    private let thumbnailStore = ThumbnailStore()

    func placeholder(in context: Context) -> NewsEntry {
        .sample(for: .all, style: .rich, family: context.family)
    }

    func snapshot(for configuration: SelectCategoryIntent, in context: Context) async -> NewsEntry {
        let category = configuration.category.newsCategory
        let style = configuration.style
        // The widget gallery needs an instant answer: cached headlines and pictures, or a redacted sample.
        if context.isPreview {
            guard let cached = cache.load(category) else {
                return .sample(for: category, style: style, family: context.family)
            }
            var entry = makeEntry(cached, category: category, style: style, family: context.family, date: Date())
            if style == .rich {
                entry.thumbnails = thumbnailStore.cachedThumbnails(
                    for: entry.items, leadItemIDs: Self.leadItemIDs(of: entry, family: context.family))
            }
            return entry
        }
        let (news, _) = await loadNews(category)
        let entry = makeEntry(news, category: category, style: style, family: context.family, date: Date())
        return await withThumbnails(entry, family: context.family)
    }

    func timeline(for configuration: SelectCategoryIntent, in context: Context) async -> Timeline<NewsEntry> {
        let now = Date()
        let category = configuration.category.newsCategory
        let (news, downloadFailed) = await loadNews(category, now: now)
        let entry = await withThumbnails(
            makeEntry(news, category: category, style: configuration.style, family: context.family, date: now),
            family: context.family)

        let nextRefresh = downloadFailed
            ? now.addingTimeInterval(Self.retryInterval)
            : max((news?.fetchedAt ?? now).addingTimeInterval(Self.refreshInterval),
                  now.addingTimeInterval(Self.minimumFetchInterval))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Returns the headlines to show, downloading them when the cache is not recent enough.
    private func loadNews(_ category: NewsCategory, now: Date = Date()) async -> (CachedNews?, downloadFailed: Bool) {
        cache.removeExpired(now: now)
        thumbnailStore.removeExpired(now: now)
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

    private func makeEntry(_ news: CachedNews?, category: NewsCategory, style: StyleOption, family: WidgetFamily,
                           date: Date) -> NewsEntry {
        let items = news?.items ?? []
        let perPage = family.headlinesPerPage(style: style)
        let pageCount = max(1, (items.count + perPage - 1) / perPage)
        let page = PageStore.page(for: category) % pageCount
        return NewsEntry(
            date: date,
            category: category,
            style: style,
            items: Array(items.dropFirst(page * perPage).prefix(perPage)),
            fetchedAt: news?.fetchedAt,
            page: page,
            pageCount: pageCount
        )
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
    /// Stories that fit on one page of each widget size.
    func headlinesPerPage(style: StyleOption) -> Int {
        switch (style, self) {
        case (.rich, .systemSmall): 1
        case (.rich, .systemMedium): 2
        case (.rich, .systemLarge): 4
        case (.rich, .systemExtraLarge): 5
        case (.headlines, .systemSmall): 3
        case (.headlines, .systemMedium): 6
        case (.headlines, .systemLarge): 9
        case (.headlines, .systemExtraLarge): 18
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
            fetchedAt: Date(),
            page: 0,
            pageCount: 3,
            isPlaceholder: redacted
        )
    }
}
