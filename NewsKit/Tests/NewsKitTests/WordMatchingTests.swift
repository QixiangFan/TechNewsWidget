import Foundation
import Testing
@testable import NewsKit

private func story(_ title: String, summary: String? = nil) -> NewsItem {
    NewsItem(title: title, url: URL(string: "https://example.com/story")!, sourceID: "s", summary: summary)
}

@Suite struct WordMatchingTests {
    @Test func matchesWholeWordsInAnyCaseAndInThePlural() {
        #expect(story("Apple's AI chips are here").mentions(anyOf: ["ai"]))
        #expect(story("AIs everywhere").mentions(anyOf: ["AI"]))
        #expect(story("AI-powered search").mentions(anyOf: ["AI"]))
        #expect(story("Small LLMs win").mentions(anyOf: ["LLM"]))
        #expect(story("GPT-5 launches").mentions(anyOf: ["gpt"]))
        #expect(story("Elon Musk says").mentions(anyOf: ["elon musk"]))
    }

    @Test func ignoresWordsInsideOtherWords() {
        #expect(!story("He said it would").mentions(anyOf: ["AI"]))
        #expect(!story("Taiwan chips").mentions(anyOf: ["AI"]))
        #expect(!story("OpenAI raises money").mentions(anyOf: ["AI"]))
        #expect(!story("ChatGPT update").mentions(anyOf: ["GPT"]))
    }

    @Test func findsLatinWordsInChineseText() {
        #expect(story("苹果发布AI新功能").mentions(anyOf: ["AI"]))
        #expect(story("ＡＩ 时代").mentions(anyOf: ["ai"]))
    }

    @Test func matchesChineseAnywhere() {
        #expect(story("华为发布新手机").mentions(anyOf: ["手机"]))
        #expect(!story("华为发布新电脑").mentions(anyOf: ["手机"]))
    }

    @Test func handlesSymbolsAndAccents() {
        #expect(story("Why C++ still matters").mentions(anyOf: ["C++"]))
        #expect(story("C++17 features").mentions(anyOf: ["c++"]))
        #expect(story("ASP.NET Core 10").mentions(anyOf: [".NET"]))
        #expect(story("Cafe opens").mentions(anyOf: ["café"]))
    }

    @Test func looksAtTheSummaryToo() {
        #expect(story("bitcoin/bitcoin", summary: "Bitcoin Core, a crypto node").mentions(anyOf: ["crypto"]))
    }

    @Test func blankWordsMatchNothing() {
        #expect(!story("Anything").mentions(anyOf: []))
        #expect(!story("Anything").mentions(anyOf: ["", "  "]))
    }
}
