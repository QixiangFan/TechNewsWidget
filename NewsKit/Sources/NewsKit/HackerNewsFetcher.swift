import Foundation

/// Parses the Algolia Hacker News search API (one request returns the whole front page).
enum HackerNewsFetcher {
    private struct Response: Decodable {
        let hits: [Hit]
    }

    private struct Hit: Decodable {
        let objectID: String
        let title: String?
        let url: String?
        let points: Int?
        let num_comments: Int?
        let created_at_i: TimeInterval?
    }

    static func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.hits.compactMap { hit in
            guard let title = hit.title else { return nil }
            // "Ask HN" / "Show HN" text posts have no external URL; link to the discussion instead.
            let link = hit.url.flatMap(URL.init(string:))
                ?? URL(string: "https://news.ycombinator.com/item?id=\(hit.objectID)")!
            return NewsItem(
                title: title,
                url: link,
                sourceID: source.id,
                date: hit.created_at_i.map(Date.init(timeIntervalSince1970:)),
                detail: "▲\(hit.points ?? 0) · 💬\(hit.num_comments ?? 0)"
            )
        }
    }
}
