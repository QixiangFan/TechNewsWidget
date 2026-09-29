import Foundation

/// All size limits for the on-disk cache, in one place.
/// With these values a category file is ~20 KB and the whole cache stays under 100 KB.
public enum CacheLimits {
    /// Items kept per category: three pages of the extra-large widget.
    public static let maxItemsPerCategory = 60
    public static let maxTitleLength = 120
    public static let maxDetailLength = 80
    /// Hard cap per category file; items are dropped from the end until the file fits.
    public static let maxFileBytes = 64 * 1024
    /// Cached headlines older than this are not shown at all.
    public static let maxAge: TimeInterval = 3 * 24 * 60 * 60
}

public struct CachedNews: Codable, Sendable {
    public let fetchedAt: Date
    public let items: [NewsItem]

    public init(fetchedAt: Date, items: [NewsItem]) {
        self.fetchedAt = fetchedAt
        self.items = items
    }
}

/// Stores the last successful fetch of each category as one small JSON file, overwritten on every save.
public struct NewsCache: Sendable {
    private let directory: URL

    /// Defaults to `<Caches>/TechNews`, which inside the sandboxed widget is its own container.
    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TechNews", isDirectory: true)
    }

    /// Returns the cached news, or nil if there is none or it is older than `CacheLimits.maxAge`.
    public func load(_ category: NewsCategory, now: Date = Date()) -> CachedNews? {
        guard let data = try? Data(contentsOf: fileURL(for: category)),
              let cached = try? Self.decoder.decode(CachedNews.self, from: data),
              now.timeIntervalSince(cached.fetchedAt) < CacheLimits.maxAge else {
            return nil
        }
        return cached
    }

    /// Writes the cache for `category` and returns the number of bytes written.
    @discardableResult
    public func save(_ news: CachedNews, for category: NewsCategory) throws -> Int {
        let data = try Self.encode(news)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: category), options: .atomic)
        return data.count
    }

    /// Encodes `news`, dropping items from the end until it fits in `CacheLimits.maxFileBytes`.
    public static func encode(_ news: CachedNews) throws -> Data {
        var items = Array(news.items.prefix(CacheLimits.maxItemsPerCategory))
        var data = try encoder.encode(CachedNews(fetchedAt: news.fetchedAt, items: items))
        while data.count > CacheLimits.maxFileBytes, !items.isEmpty {
            items.removeLast(max(1, items.count / 10))
            data = try encoder.encode(CachedNews(fetchedAt: news.fetchedAt, items: items))
        }
        return data
    }

    private func fileURL(for category: NewsCategory) -> URL {
        directory.appendingPathComponent("news-\(category.rawValue).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
