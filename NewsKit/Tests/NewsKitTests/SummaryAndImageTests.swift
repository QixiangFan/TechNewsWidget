import Foundation
import Testing
@testable import NewsKit

private let feedSource = NewsSource(id: "test", name: "Test", category: .chinese, url: "https://example.com/feed")

/// Fixtures are trimmed copies of what the real feeds send.
@Suite struct SummaryTextTests {
    @Test func dropsDatelineEditorNotesAndInlineTagSpacing() {
        let html = """
        <p data-vmark="d21f">IT之家 9 月 30 日消息，OpenAI 宣布<strong>升级插件扩展</strong>（IT之家注：现汇率约合 1 元）。</p>
        <p>▲ IT之家 实拍</p><p>第二段。</p>
        """
        #expect(html.summaryText(maxLength: 100) == "OpenAI 宣布升级插件扩展。 第二段。")
    }

    @Test func keepsTheEllipsisOfAReadMoreLink() {
        let html = #"除了首页时间流，我们决定重启周报 ...<a href="https://sspai.com/post/1" target="_blank">查看全文</a>"#
        #expect(html.summaryText(maxLength: 100) == "除了首页时间流，我们决定重启周报…")
        #expect("全新 Apple Watch，有哪些升级？ 查看全文".summaryText(maxLength: 100) == "全新 Apple Watch，有哪些升级？")
    }

    @Test func dropsNewsletterPlugsBylinesAndCredits() {
        let ifanr = "现在，人人都可以用「万物皆插件」了<p>#欢迎关注爱范儿官方微信公众号：爱范儿（微信号：ifanr），更多精彩内容第一时间为您奉上。</p>"
        #expect(ifanr.summaryText(maxLength: 100) == "现在，人人都可以用「万物皆插件」了")

        let geekpark = "<p>作者｜Techno 之王</p><p>编辑｜靖宇</p><p>头图来源：Manus</p><p>当地时间 9 月 28 日，外媒披露了一份招股书。</p>"
        #expect(geekpark.summaryText(maxLength: 100) == "当地时间 9 月 28 日，外媒披露了一份招股书。")

        let promo = "<p>&gt;下载少数派客户端，解锁全新阅读体验</p><p>本文为会员文章，订阅后可阅读全文。</p>"
        #expect(promo.summaryText(maxLength: 100) == "")
    }

    @Test func dropsParagraphsThatRepeatTheTitle() {
        let html = "<p>OpenAI 称与苹果合作效果不佳</p><p>F-Droid 2.0 发布</p>"
        #expect(html.summaryText(maxLength: 100, droppingTitle: "派早报：OpenAI 称与苹果合作效果不佳") == "F-Droid 2.0 发布")
    }

    @Test func skipsCaptionsAndStopsAtMaxLength() {
        let html = """
        <figure><img src="a.jpg"><figcaption>Discounted in black and white. | Image: The Verge</figcaption></figure>
        <p>\(String(repeating: "word ", count: 40))</p><p>Never reached.</p>
        """
        let summary = html.summaryText(maxLength: 50)
        #expect(summary.hasPrefix("word word"))
        #expect(summary.hasSuffix("…"))
        #expect(summary.count <= 50)
    }

    @Test func newsItemDropsSummariesThatOnlyRepeatTheTitle() {
        let item = NewsItem(title: "Same text", url: URL(string: "https://example.com")!, sourceID: "s",
                            summary: "<p>Same text</p>")
        #expect(item.summary == nil)
    }
}

@Suite struct FeedImageTests {
    private func firstItem(_ itemXML: String) throws -> NewsItem {
        let xml = """
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
             xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
        <item><title>T</title><link>https://example.com/news/1</link>\(itemXML)</item>
        </channel></rss>
        """
        return try #require(FeedParser.parse(Data(xml.utf8), source: feedSource).first)
    }

    @Test func prefersTheFeedsLeadImage() throws {
        let item = try firstItem("""
        <description><![CDATA[<p><img src="https://example.com/inline.jpg">Text</p>]]></description>
        <media:content url="https://cdn.example.com/lead-1152x648.jpg" medium="image" width="1152" height="648"/>
        """)
        #expect(item.imageURL?.absoluteString == "https://cdn.example.com/lead-1152x648.jpg")
        #expect(item.summary == "Text")
    }

    @Test func readsEnclosuresAndPlainImageElements() throws {
        let enclosure = try firstItem(#"<enclosure url="https://example.com/e.jpg" type="image/jpeg" length="1"/>"#)
        #expect(enclosure.imageURL?.absoluteString == "https://example.com/e.jpg")

        let audio = try firstItem(#"<enclosure url="https://example.com/e.mp3" type="audio/mpeg" length="1"/>"#)
        #expect(audio.imageURL == nil)

        let ifanr = try firstItem("<image>https://s3.ifanr.com/wp-content/uploads/2026/09/222-5.png</image>")
        #expect(ifanr.imageURL?.absoluteString == "https://s3.ifanr.com/wp-content/uploads/2026/09/222-5.png")
    }

    @Test func fallsBackToTheFirstUsableImgInTheArticle() throws {
        let item = try firstItem("""
        <description>Short dek</description>
        <content:encoded><![CDATA[
          <img src="data:image/png;base64,AAAA"><img src="https://s.w.org/images/core/emoji/15/svg/1f600.svg">
          <img src="/pixel.gif"><img class="wide" src='/uploads/photo.jpg?x=1&#038;y=2'>
        ]]></content:encoded>
        """)
        #expect(item.imageURL?.absoluteString == "https://example.com/uploads/photo.jpg?x=1&y=2")
        #expect(item.summary == "Short dek")
    }

    @Test func usesTheArticleAsSummaryWhenThereIsNoDescription() throws {
        let item = try firstItem("<content:encoded><![CDATA[<p>Only the article.</p>]]></content:encoded>")
        #expect(item.summary == "Only the article.")
        #expect(item.imageURL == nil)
    }
}

@Suite struct CacheCompatibilityTests {
    @Test func readsCachesWrittenBeforeSummariesAndImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let oldFormat = #"{"fetchedAt": 1790000000, "items": [{"t": "Old", "u": "https:\/\/example.com\/old", "s": "hn"}]}"#
        try Data(oldFormat.utf8).write(to: directory.appendingPathComponent("news-hackerNews.json"))

        let item = try #require(NewsCache(directory: directory).load(.hackerNews, now: now)?.items.first)
        #expect(item.title == "Old")
        #expect(item.summary == nil)
        #expect(item.imageURL == nil)
    }
}
