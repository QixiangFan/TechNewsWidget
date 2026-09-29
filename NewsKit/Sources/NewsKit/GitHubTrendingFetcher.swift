import Foundation

/// GitHub has no official "trending" API, so this scrapes github.com/trending.
/// If the page layout changes and nothing can be parsed, `NewsService` falls back to `searchURL`.
enum GitHubTrendingFetcher {
    /// Repositories created in the last week, sorted by stars.
    static func searchURL(now: Date = Date()) -> URL {
        let weekAgo = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: now) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: weekAgo)
        return URL(string: "https://api.github.com/search/repositories?q=created:%3E\(day)&sort=stars&order=desc&per_page=30")!
    }

    // MARK: Trending page

    static func parseTrendingPage(_ data: Data, source: NewsSource) -> [NewsItem] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Each repository is rendered as <article class="Box-row">…</article>.
        return html.components(separatedBy: "<article class=\"Box-row\"").dropFirst().compactMap { row in
            guard let path = firstMatch(in: row, pattern: #"<h2[^>]*>\s*<a[^>]*href="/([^"/]+/[^"/]+)""#),
                  let url = URL(string: "https://github.com/\(path)") else {
                return nil
            }
            let description = firstMatch(in: row, pattern: #"<p class="col-9[^"]*">([\s\S]*?)</p>"#)
            let language = firstMatch(in: row, pattern: #"itemprop="programmingLanguage">([^<]*)<"#)
            let starsToday = firstMatch(in: row, pattern: #"([\d,]+) stars? today"#)
            return NewsItem(
                title: path,
                url: url,
                sourceID: source.id,
                detail: detailLine(stars: starsToday.map { "+\($0)★" }, language: language, description: description)
            )
        }
    }

    // MARK: Search API fallback

    private struct SearchResponse: Decodable {
        let items: [Repo]
    }

    private struct Repo: Decodable {
        let full_name: String
        let html_url: URL
        let description: String?
        let language: String?
        let stargazers_count: Int
        let created_at: Date?
    }

    static func parseSearchResponse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SearchResponse.self, from: data).items.map { repo in
            NewsItem(
                title: repo.full_name,
                url: repo.html_url,
                sourceID: source.id,
                date: repo.created_at,
                detail: detailLine(stars: "\(repo.stargazers_count)★", language: repo.language, description: repo.description)
            )
        }
    }

    // MARK: Helpers

    /// "+1,234★ · Swift · A short description", skipping missing parts.
    private static func detailLine(stars: String?, language: String?, description: String?) -> String {
        [stars, language, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Returns capture group 1 of the first match.
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
