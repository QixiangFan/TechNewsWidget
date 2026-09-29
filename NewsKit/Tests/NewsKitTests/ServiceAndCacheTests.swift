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

    @Test func keepsAtMostMaxItemsPerCategory() throws {
        let items = (0..<200).map { item("i\($0)") }
        let data = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        #expect(try decoder.decode(CachedNews.self, from: data).items.count == CacheLimits.maxItemsPerCategory)
    }

    @Test func trimsItemsUntilFileFitsHardCap() throws {
        // Very long URLs push 60 items well past the 64 KB cap.
        let longPath = String(repeating: "p", count: 2_000)
        let items = (0..<CacheLimits.maxItemsPerCategory).map { item("\(longPath)\($0)") }
        let data = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items))
        #expect(data.count <= CacheLimits.maxFileBytes)
    }
}
