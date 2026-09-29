import Foundation
import Testing
@testable import NewsKit

private let feedSource = NewsSource(id: "test", name: "Test", category: .english, url: "https://example.com/feed")

@Suite struct FeedParserTests {
    @Test func parsesRSS2Items() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Channel title must be ignored</title>
          <link>https://example.com/</link>
          <item>
            <title><![CDATA[ Apple &amp; Google  announce
              something ]]></title>
            <link> https://example.com/a </link>
            <description><![CDATA[<p>Body is ignored</p>]]></description>
            <pubDate>Tue, 29 Sep 2026 11:28:25 +0800</pubDate>
          </item>
          <item>
            <title>Second</title>
            <link>https://example.com/b</link>
            <pubDate>Tue, 29 Sep 2026 04:53:27 GMT</pubDate>
          </item>
        </channel></rss>
        """
        let items = try FeedParser.parse(Data(xml.utf8), source: feedSource)
        #expect(items.count == 2)
        #expect(items[0].title == "Apple & Google announce something")
        #expect(items[0].url.absoluteString == "https://example.com/a")
        #expect(items[0].date == Date(timeIntervalSince1970: 1_790_652_505))
        #expect(items[1].date == Date(timeIntervalSince1970: 1_790_657_607))
    }

    @Test func parsesAtomEntriesUsingAlternateLink() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <link rel="self" href="https://example.com/feed.xml"/>
          <entry>
            <title type="html">Nothing&#8217;s new phone</title>
            <link rel="self" href="https://example.com/self"/>
            <link rel="alternate" type="text/html" href="https://example.com/story"/>
            <updated>2026-09-29T02:00:00+00:00</updated>
            <published>2026-09-29T01:00:00+00:00</published>
            <author><name>Author name is not a title</name></author>
          </entry>
        </feed>
        """
        let items = try FeedParser.parse(Data(xml.utf8), source: feedSource)
        #expect(items.count == 1)
        #expect(items[0].title == "Nothing’s new phone")
        #expect(items[0].url.absoluteString == "https://example.com/story")
        #expect(items[0].date == Date(timeIntervalSince1970: 1_790_643_600))
    }

    @Test func rejectsHTMLPages() {
        let html = "<!DOCTYPE html><html><head><style>* { }</style></head><body>blocked</body></html>"
        #expect(throws: NewsError.self) {
            try FeedParser.parse(Data(html.utf8), source: feedSource)
        }
    }
}

@Suite struct APIParserTests {
    @Test func parsesHackerNewsAndLinksTextPostsToDiscussion() throws {
        let json = """
        {"hits": [
          {"objectID": "1", "title": "Show HN: A thing", "url": null, "points": 12, "num_comments": 3, "created_at_i": 1790618291},
          {"objectID": "2", "title": "Link post", "url": "https://example.com/x", "points": 5, "num_comments": 0}
        ]}
        """
        let source = NewsSource.named("hn")!
        let items = try HackerNewsFetcher.parse(Data(json.utf8), source: source)
        #expect(items.map(\.url.absoluteString) == ["https://news.ycombinator.com/item?id=1", "https://example.com/x"])
        #expect(items[0].detail == "▲12 · 💬3")
        #expect(items[1].date == nil)
    }

    @Test func parsesGitHubTrendingPage() {
        let html = """
        <article class="Box-row">
          <h2 class="h3 lh-condensed">
            <a data-hydro-click="{}" href="/owner/repo" class="Link">owner / repo</a>
          </h2>
          <p class="col-9 color-fg-muted my-1 tmp-pr-4">
            A fast &amp; local thing.
          </p>
          <span itemprop="programmingLanguage">Swift</span>
          <span class="d-inline-block float-sm-right">1,234 stars today</span>
        </article>
        <article class="Box-row">
          <h2 class="h3 lh-condensed"><a href="/other/project">other / project</a></h2>
        </article>
        """
        let items = GitHubTrendingFetcher.parseTrendingPage(Data(html.utf8), source: NewsSource.named("github")!)
        #expect(items.map(\.title) == ["owner/repo", "other/project"])
        #expect(items[0].url.absoluteString == "https://github.com/owner/repo")
        #expect(items[0].detail == "+1,234★ · Swift · A fast & local thing.")
        #expect(items[1].detail == nil)
    }

    @Test func parsesGitHubSearchFallback() throws {
        let json = """
        {"total_count": 1, "items": [{"full_name": "a/b", "html_url": "https://github.com/a/b",
          "description": null, "language": "Rust", "stargazers_count": 42, "created_at": "2026-09-25T10:00:00Z"}]}
        """
        let items = try GitHubTrendingFetcher.parseSearchResponse(Data(json.utf8), source: NewsSource.named("github")!)
        #expect(items.count == 1)
        #expect(items[0].detail == "42★ · Rust")
        #expect(items[0].date != nil)
    }
}

@Suite struct TextCleaningTests {
    @Test func truncatesWithEllipsis() {
        let text = String(repeating: "a", count: 200).cleanedText(maxLength: 10)
        #expect(text == "aaaaaaaaa…")
        #expect(text.count == 10)
    }

    @Test func stripsTagsAndDecodesEntities() {
        #expect("<b>Hi</b>&nbsp;&quot;there&quot; &#x4F60;&#22909;".cleanedText(maxLength: 50) == "Hi \"there\" 你好")
        #expect("Unknown &bogus; stays".cleanedText(maxLength: 50) == "Unknown &bogus; stays")
    }
}
