import Foundation

/// A group of sources the user can pick for one widget instance.
public enum NewsCategory: String, CaseIterable, Codable, Sendable {
    case all
    case chinese
    case english
    case hackerNews
    case github
}

public struct NewsSource: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// RSS 2.0, RSS 1.0 (RDF) or Atom feed.
        case feed
        /// WordPress REST API, which unlike RSS carries each post's featured image.
        /// Falls back to the site's RSS feed.
        case wordpress
        /// Hacker News front page via the Algolia search API.
        case hackerNews
        /// github.com/trending page, with the GitHub search API as a fallback.
        case githubTrending
    }

    public let id: String
    /// Proper name of the outlet, shown as-is in every language.
    public let name: String
    public let category: NewsCategory
    public let url: URL
    public let kind: Kind

    public init(id: String, name: String, category: NewsCategory, url: String, kind: Kind = .feed) {
        self.id = id
        self.name = name
        self.category = category
        self.url = URL(string: url)!
        self.kind = kind
    }
}

extension NewsSource {
    /// Every built-in source, in the order they are interleaved.
    public static let all: [NewsSource] = [
        NewsSource(id: "ithome", name: "IT之家", category: .chinese, url: "https://www.ithome.com/rss/"),
        NewsSource(id: "sspai", name: "少数派", category: .chinese, url: "https://sspai.com/feed"),
        NewsSource(id: "ifanr", name: "爱范儿", category: .chinese, url: "https://www.ifanr.com/feed"),
        NewsSource(id: "geekpark", name: "极客公园", category: .chinese, url: "https://www.geekpark.net/rss"),
        NewsSource(id: "verge", name: "The Verge", category: .english, url: "https://www.theverge.com/rss/index.xml"),
        NewsSource(id: "techcrunch", name: "TechCrunch", category: .english,
                   url: "https://techcrunch.com/wp-json/wp/v2/posts?per_page=20&_fields=title,link,excerpt,date_gmt,jetpack_featured_media_url",
                   kind: .wordpress),
        NewsSource(id: "ars", name: "Ars Technica", category: .english, url: "https://feeds.arstechnica.com/arstechnica/index"),
        NewsSource(id: "hn", name: "Hacker News", category: .hackerNews,
                   url: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30", kind: .hackerNews),
        NewsSource(id: "github", name: "GitHub", category: .github,
                   url: "https://github.com/trending?since=daily", kind: .githubTrending),
    ]

    public static func sources(for category: NewsCategory) -> [NewsSource] {
        category == .all ? all : all.filter { $0.category == category }
    }

    public static func named(_ id: String) -> NewsSource? {
        all.first { $0.id == id }
    }
}
