import Foundation
import Testing
@testable import NewsKit

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func story(_ title: String, _ source: String, hoursAgo: Double? = 1) -> NewsItem {
    NewsItem(title: title, url: URL(string: "https://\(source).example/\(UUID().uuidString)")!, sourceID: source,
             date: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) })
}

// Headlines of 2026-09-29, a few per outlet.
private let geekpark = [
    story("OpenAI 推出个人 AI 智能体 dots；传豆包将推个人 AI 产品「Spell」；SpaceX 发射星舰成功入轨 | 极客早知道", "geekpark"),
    story("AMD 82 亿美元收购 World Labs，买的不只是世界模型", "geekpark"),
    story("从数人头到数智能体：一场正在发生的企业生产力换血", "geekpark"),
]
private let ithome = [
    story("AT&T 与康宁达成超 30 亿美元光纤与电缆供应协议", "ithome"),
    story("OpenAI 推出全天候 AI 智能体 Dots，相关域名已被马斯克拿下", "ithome"),
    story("百度地图 V22 版本发布：车道级导航 4.0、SR 导航 2.0、全域护航系统", "ithome"),
]
private let ars = [
    story("Most powerful obesity drug yet: People lost up to 25% of weight in trial", "ars"),
    story("AMD acquires World Labs AI startup, upping the ante against Nvidia", "ars"),
    story("NASA has a Dragon dilemma, and there appear to be no good answers", "ars"),
]
private let techcrunch = [
    story("a16z-backed EliseAI raises $350M, doubles valuation to $4B", "techcrunch"),
    story("OpenAI launches GPT-6.1 Sol, says it nearly matches GPT-6 Astra and costs less", "techcrunch"),
]
private let hn = [
    story("GPT 6.1 Sol: Near-Astra intelligence for a fifth of the price", "hn"),
    story("How Delhi cut electricity loss from 50 to 5 percent", "hn"),
]

@Suite struct TopStoriesTests {
    @Test func picksStoriesThatOtherOutletsReport() {
        let top = TopStories.pick(from: [ithome, geekpark, ars, techcrunch, hn], now: now)
        let titles = top.map(\.title)
        #expect(titles.contains { $0.contains("World Labs") })
        #expect(titles.contains { $0.contains("GPT") && $0.contains("Sol") })
        #expect(!titles.contains { $0.contains("obesity") || $0.contains("康宁") })
    }

    @Test func matchesAcrossLanguages() {
        let coverage = TopStories.coverage(in: [geekpark, ars])
        #expect(coverage[geekpark[1].id] == ["ars"])
        #expect(coverage[ars[1].id] == ["geekpark"])
        #expect(coverage[ars[0].id] == nil)
    }

    @Test func picksEachEventOnce() {
        let top = TopStories.pick(from: [ars, geekpark, techcrunch, hn], now: now)
        #expect(top.filter { $0.title.contains("World Labs") }.count == 1)
        #expect(top.filter { $0.title.contains("Sol") }.count == 1)
    }

    @Test func neverPicksDigestsButCountsThem() {
        // The digest backs up ithome's Dots story, yet only that story is picked.
        let top = TopStories.pick(from: [geekpark, ithome], now: now)
        #expect(top.map(\.id).contains(ithome[1].id))
        #expect(!top.contains { TopStories.isDigest($0.title) })
        #expect(TopStories.isDigest("派早报：OpenAI 发布 Dot 智能体"))
        #expect(TopStories.isDigest("The Morning After: Apple's new CEO"))
        #expect(!TopStories.isDigest("Mornington Peninsula gets fiber"))
    }

    @Test func commonChineseWordsAloneDoNotMatch() {
        // Both mention 亿美元 and 智能体, which says nothing about being the same event.
        let coverage = TopStories.coverage(in: [[geekpark[2], geekpark[1]], [ithome[0], ithome[1]]])
        #expect(coverage[geekpark[1].id] == nil)
        #expect(coverage[geekpark[2].id] == nil)
    }

    @Test func picksNothingWithoutCoverageOrWithOneSource() {
        #expect(TopStories.pick(from: [[ars[0], ars[2]], [hn[1]]], now: now).isEmpty)
        #expect(TopStories.pick(from: [ars + techcrunch.map { story($0.title, "ars") }], now: now).isEmpty)
        #expect(TopStories.pick(from: [], now: now).isEmpty)
    }

    @Test func ranksStaleStoriesBelowFreshOnes() {
        let stale = [story("AMD acquires World Labs AI startup", "ars", hoursAgo: 48),
                     story("OpenAI launches GPT-6.1 Sol", "ars", hoursAgo: 2)]
        let others = [story("AMD 收购 World Labs", "geekpark", hoursAgo: 48), story("GPT-6.1 Sol 推出", "ifanr")]
        let top = TopStories.pick(from: [stale, others], now: now, count: 1)
        #expect(top.first?.title.contains("Sol") == true)
    }

    @Test func limitsEachSourceToTwoStories() {
        let busy = (1...4).map { story("Topic\($0) Alpha\($0) news", "busy") }
        let echo = (1...4).map { story("Topic\($0) Alpha\($0) report", "echo") }
        let top = TopStories.pick(from: [busy, echo], now: now)
        #expect(top.count == 4)
        #expect(top.filter { $0.sourceID == "busy" }.count == 2)
    }

    @Test func splitsTitlesIntoWords() {
        let words = TopStories.words(in: "OpenAI 推出 GPT‑6.1 Sol，M4 版 iPad 降价 30% for the win")
        #expect(words.isSuperset(of: ["openai", "gpt", "6.1", "sol", "m4", "ipad", "win", "推出", "降价"]))
        #expect(!words.contains("30"))
        #expect(!words.contains("the"))
        #expect(!words.contains("for"))
    }

    @Test func movesStoriesToFrontKeepingTheRest() {
        let items = ars + hn
        let moved = TopStories.movedToFront(items, ids: [hn[0].id, "missing", ars[1].id])
        #expect(moved.map(\.id) == [hn[0], ars[1], ars[0], ars[2], hn[1]].map(\.id))
    }
}

@Suite struct InterleaveKeepingTests {
    @Test func keepsRequiredStoriesPastTheLimit() {
        let first = (0..<5).map { story("a\($0)", "a") }
        let second = (0..<5).map { story("b\($0)", "b") }
        let required = [second[4], first[0]]
        let merged = NewsService.interleave([first, second], limit: 4, keeping: required)
        #expect(merged.count == 4)
        #expect(merged.map(\.title) == ["a0", "b0", "a1", "b4"])
    }
}
