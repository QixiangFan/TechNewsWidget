import Foundation

/// Parses the WordPress REST API (`/wp-json/wp/v2/posts`). Unlike the site's RSS feed it includes
/// each post's featured image. If the API fails, `NewsService` falls back to `feedURL(for:)`.
enum WordPressFetcher {
    private struct Post: Decodable {
        struct Rendered: Decodable {
            let rendered: String
        }

        let link: String
        let title: Rendered
        let excerpt: Rendered?
        /// "2026-09-29T17:45:51": UTC, but without a zone designator.
        let date_gmt: String?
        /// Empty when the post has no featured image.
        let jetpack_featured_media_url: String?
    }

    static func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        try JSONDecoder().decode([Post].self, from: data).compactMap { post in
            guard !post.title.rendered.isEmpty, let url = URL(string: post.link) else { return nil }
            return NewsItem(
                title: post.title.rendered,
                url: url,
                sourceID: source.id,
                date: post.date_gmt.flatMap { FeedDate.parse($0 + "Z") },
                summary: post.excerpt?.rendered,
                imageURL: post.jetpack_featured_media_url.flatMap(URL.init(string:))
            )
        }
    }

    /// The site's standard RSS feed, e.g. https://techcrunch.com/feed/ for the TechCrunch API.
    static func feedURL(for apiURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = apiURL.scheme
        components.host = apiURL.host
        components.path = "/feed/"
        return components.url ?? apiURL
    }
}
