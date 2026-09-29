import Foundation

/// All size limits for the on-disk cache, in one place.
/// With these values the headline files total about 100 KB and the thumbnails at most 300 KB.
public enum CacheLimits {
    /// Items kept per category: three pages of the extra-large widget.
    public static let maxItemsPerCategory = 60
    public static let maxTitleLength = 120
    public static let maxDetailLength = 80
    public static let maxSummaryLength = 100
    /// Hard cap per category file; items are dropped from the end until the file fits.
    public static let maxFileBytes = 64 * 1024
    /// Cached headlines and thumbnails older than this are deleted.
    public static let maxAge: TimeInterval = 3 * 24 * 60 * 60
    /// Thumbnails are JPEGs whose longer side is at most this many pixels (typically 5–20 KB each).
    public static let thumbnailMaxPixelSize = 320
    /// The lead story of the large widgets is shown about 330 points wide, so it gets a sharper copy (typically about 30 KB).
    public static let leadThumbnailMaxPixelSize = 640
    /// Hard cap for all thumbnails together; the oldest are deleted first.
    public static let maxThumbnailBytes = 300 * 1024
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
    /// `<Caches>/TechNews`, which inside the sandboxed widget is its own container.
    public static let defaultDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TechNews", isDirectory: true)

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    /// Returns the cached news, or nil if there is none or it is older than `CacheLimits.maxAge`.
    /// Expired or unreadable files are deleted on the spot.
    public func load(_ category: NewsCategory, now: Date = Date()) -> CachedNews? {
        let url = fileURL(for: category)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cached = try? Self.decoder.decode(CachedNews.self, from: data),
              now.timeIntervalSince(cached.fetchedAt) < CacheLimits.maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return cached
    }

    /// Deletes every expired or unreadable cache file, including those of categories no widget
    /// shows any more (their files would otherwise never be overwritten). Returns how many were removed.
    @discardableResult
    public func removeExpired(now: Date = Date()) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for url in files where url.lastPathComponent.hasPrefix("news-") && url.pathExtension == "json" {
            let cached = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(CachedNews.self, from: $0) }
            if let cached, now.timeIntervalSince(cached.fetchedAt) < CacheLimits.maxAge {
                continue
            }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
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
        // Store "https://a/b" rather than "https:\/\/a\/b".
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
