import Foundation
import Testing
@testable import NewsKit

private func item(_ path: String, source: String = "s") -> NewsItem {
    NewsItem(title: path, url: URL(string: "https://example.com/\(path)")!, sourceID: source)
}

@Suite struct InterleaveTests {
    @Test func alternatesBetweenSourcesAndDropsDuplicates() {
        let first = [item("a1"), item("shared"), item("a3")]
        let second = [item("b1"), item("shared"), item("b3"), item("b4")]
        let merged = NewsService.interleave([first, second], limit: 100)
        #expect(merged.map(\.title) == ["a1", "b1", "shared", "a3", "b3", "b4"])
    }

    @Test func stopsAtLimit() {
        let list = (0..<10).map { item("i\($0)") }
        #expect(NewsService.interleave([list], limit: 4).count == 4)
    }
}

@Suite struct NewsCacheTests {
    private func temporaryCache() -> NewsCache {
        NewsCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func roundTripsAndExpires() throws {
        let cache = temporaryCache()
        let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.save(CachedNews(fetchedAt: fetchedAt, items: [item("x")]), for: .english)

        let loaded = try #require(cache.load(.english, now: fetchedAt.addingTimeInterval(60)))
        #expect(loaded.items.map(\.title) == ["x"])
        #expect(cache.load(.chinese, now: fetchedAt) == nil)
        #expect(cache.load(.english, now: fetchedAt.addingTimeInterval(CacheLimits.maxAge + 1)) == nil)
    }

    @Test func removesExpiredAndUnreadableFilesOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true)
        let cache = NewsCache(directory: directory)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.save(CachedNews(fetchedAt: now, items: [item("fresh")]), for: .english)
        try cache.save(CachedNews(fetchedAt: now.addingTimeInterval(-CacheLimits.maxAge - 1), items: [item("old")]), for: .github)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("news-chinese.json"))
        try Data("keep".utf8).write(to: directory.appendingPathComponent("unrelated.txt"))

        #expect(cache.removeExpired(now: now) == 2)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining == ["news-english.json", "unrelated.txt"])
        #expect(cache.load(.english, now: now)?.items.map(\.title) == ["fresh"])
    }

    @Test func loadDeletesExpiredFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true)
        let cache = NewsCache(directory: directory)
        let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.save(CachedNews(fetchedAt: fetchedAt, items: [item("x")]), for: .hackerNews)

        #expect(cache.load(.hackerNews, now: fetchedAt.addingTimeInterval(CacheLimits.maxAge + 1)) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func keepsAtMostMaxItemsPerCategory() throws {
        let items = (0..<200).map { item("i\($0)") }
        let data = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        #expect(try decoder.decode(CachedNews.self, from: data).items.count == CacheLimits.maxItemsPerCategory)
    }

    @Test func remembersRequestedSources() throws {
        let cache = temporaryCache()
        let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.save(CachedNews(fetchedAt: fetchedAt, items: [item("x")], sourceIDs: ["verge", "ars"]), for: .english)
        #expect(cache.load(.english, now: fetchedAt)?.sourceIDs == ["verge", "ars"])
    }

    @Test func readsCachesWrittenBeforeSourceIDs() throws {
        let json = #"{"fetchedAt":1790000000,"items":[{"t":"x","u":"https://example.com/x","s":"hn"}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let cached = try decoder.decode(CachedNews.self, from: Data(json.utf8))
        #expect(cached.items.map(\.title) == ["x"])
        #expect(cached.sourceIDs == nil)
    }

    @Test func measuresAndClearsHeadlinesAndThumbnails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true)
        let cache = NewsCache(directory: directory)
        #expect(cache.usage() == CacheUsage())

        let written = try cache.save(CachedNews(fetchedAt: Date(), items: [item("x")]), for: .english)
        let thumbs = directory.appendingPathComponent("thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: thumbs.appendingPathComponent("a.jpg"))
        try Data(count: 500).write(to: thumbs.appendingPathComponent("b-640.jpg"))

        let usage = cache.usage()
        #expect(usage.headlineBytes == written)
        #expect(usage.thumbnailBytes == 1_500)
        #expect(usage.thumbnailCount == 2)
        #expect(usage.totalBytes == written + 1_500)
        #expect(usage.lastSaved != nil)

        #expect(cache.removeAll())
        #expect(cache.usage() == CacheUsage())
        #expect(cache.load(.english) == nil)
    }

    @Test func trimsItemsUntilFileFitsHardCap() throws {
        // Very long URLs push 60 items well past the 64 KB cap.
        let longPath = String(repeating: "p", count: 2_000)
        let items = (0..<CacheLimits.maxItemsPerCategory).map { item("\(longPath)\($0)") }
        let data = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items))
        #expect(data.count <= CacheLimits.maxFileBytes)
    }
}
