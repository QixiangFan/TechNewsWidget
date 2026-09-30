import Foundation
import os

public enum NewsError: Error, LocalizedError {
    case badStatus(String, Int)
    case unreadableFeed(String, String)

    public var errorDescription: String? {
        switch self {
        case let .badStatus(sourceID, code): "\(sourceID): HTTP \(code)"
        case let .unreadableFeed(sourceID, reason): "\(sourceID): \(reason)"
        }
    }
}

public struct NewsFetchResult: Sendable {
    public let items: [NewsItem]
    /// IDs of the sources that failed; the rest still contributed items.
    public let failedSourceIDs: [String]
}

/// Downloads and merges headlines. Every source is fetched concurrently and a failing
/// source never blocks the others.
public struct NewsService: Sendable {
    /// Upper bound per source before merging, so one busy feed cannot crowd out the rest.
    public static let maxItemsPerSource = 30

    static let logger = Logger(subsystem: "com.qixiangfan.TechNews", category: "NewsKit")

    private let session: URLSession

    public init(session: URLSession = .newsKit) {
        self.session = session
    }

    /// Fetches every source in `category` and interleaves them into one list.
    public func fetch(_ category: NewsCategory) async -> NewsFetchResult {
        await fetch(NewsSource.sources(for: category))
    }

    /// Fetches `sources` and interleaves them into one list, in the order given.
    public func fetch(_ sources: [NewsSource]) async -> NewsFetchResult {
        var itemsBySource: [String: [NewsItem]] = [:]
        var failed: [String] = []

        await withTaskGroup(of: (String, Result<[NewsItem], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return (source.id, .success(try await fetchItems(from: source)))
                    } catch {
                        return (source.id, .failure(error))
                    }
                }
            }
            for await (sourceID, result) in group {
                switch result {
                case let .success(items):
                    itemsBySource[sourceID] = items
                case let .failure(error):
                    failed.append(sourceID)
                    Self.logger.error("Fetching \(sourceID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let lists = sources.compactMap { itemsBySource[$0.id] }
        return NewsFetchResult(
            items: Self.interleave(lists, limit: CacheLimits.maxItemsPerCategory),
            failedSourceIDs: failed
        )
    }

    /// Fetches a single source, capped at `maxItemsPerSource`.
    public func fetchItems(from source: NewsSource) async throws -> [NewsItem] {
        let items: [NewsItem]
        switch source.kind {
        case .feed:
            items = try FeedParser.parse(try await data(from: source.url, sourceID: source.id), source: source)
        case .wordpress:
            let posts = try? WordPressFetcher.parse(try await data(from: source.url, sourceID: source.id), source: source)
            if let posts, !posts.isEmpty {
                items = posts
            } else {
                Self.logger.notice("WordPress API of \(source.id, privacy: .public) unavailable, using its RSS feed")
                let feed = try await data(from: WordPressFetcher.feedURL(for: source.url), sourceID: source.id)
                items = try FeedParser.parse(feed, source: source)
            }
        case .hackerNews:
            items = try HackerNewsFetcher.parse(try await data(from: source.url, sourceID: source.id), source: source)
        case .githubTrending:
            let page = try? await data(from: source.url, sourceID: source.id)
            let trending = page.map { GitHubTrendingFetcher.parseTrendingPage($0, source: source) } ?? []
            if trending.isEmpty {
                Self.logger.notice("GitHub trending page unavailable, using search API")
                let fallback = try await data(from: GitHubTrendingFetcher.searchURL(), sourceID: source.id)
                items = try GitHubTrendingFetcher.parseSearchResponse(fallback, source: source)
            } else {
                items = trending
            }
        }
        return Array(items.prefix(Self.maxItemsPerSource))
    }

    /// Round-robin merge so every source shows up near the top, dropping duplicate URLs.
    public static func interleave(_ lists: [[NewsItem]], limit: Int) -> [NewsItem] {
        var merged: [NewsItem] = []
        var seen = Set<URL>()
        let longest = lists.map(\.count).max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count {
                let item = list[index]
                if seen.insert(item.url).inserted {
                    merged.append(item)
                    if merged.count == limit { return merged }
                }
            }
        }
        return merged
    }

    private func data(from url: URL, sourceID: String) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsError.badStatus(sourceID, http.statusCode)
        }
        return data
    }
}

extension URLSession {
    /// Session used for all fetching. It is ephemeral and has no URLCache, so raw
    /// feed / HTML responses are never written to disk; only the small `NewsCache` is.
    public static let newsKit: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TechNews/1.0",
        ]
        return URLSession(configuration: configuration)
    }()
}
