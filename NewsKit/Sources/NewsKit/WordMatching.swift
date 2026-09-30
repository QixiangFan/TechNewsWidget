import Foundation

extension NewsItem {
    /// True when the title or summary mentions one of `words` (the app's muted words), ignoring
    /// case, accents and full-width letters.
    ///
    /// Words match as whole words, also in the plural: "AI" hides "AI chips", "AIs" and "苹果发布AI新功能",
    /// but not "said", "Taiwan" or "OpenAI". Chinese and Japanese words match anywhere, since those
    /// languages don't put spaces between words. Blank words match nothing.
    public func mentions(anyOf words: [String]) -> Bool {
        let patterns = words.compactMap(Self.pattern(for:))
        guard !patterns.isEmpty else { return false }
        let text = (title + "\n" + (summary ?? "")).foldedForMatching
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// A regular expression that finds `word` in folded text, or nil for a blank word.
    private static func pattern(for word: String) -> String? {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines).foldedForMatching
        guard !word.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: word)
        if word.range(of: ideograph, options: .regularExpression) != nil {
            return escaped
        }
        // Only an edge that is a letter or digit needs a word boundary, so "C++" still finds "C++17".
        let isWordEdge: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let start = word.first.map(isWordEdge) == true ? "(?<!\(wordCharacter))" : ""
        let end = word.last.map(isWordEdge) == true ? "(?:e?s)?(?!\(wordCharacter))" : ""
        return start + escaped + end
    }

    /// Chinese characters and Japanese kana.
    private static let ideograph = #"[\p{Han}\p{Hiragana}\p{Katakana}]"#
    /// A letter or digit of a script that puts spaces between words, so "AI" right after "苹果" still counts.
    private static let wordCharacter = #"[[\p{L}\p{N}]--[\p{Han}\p{Hiragana}\p{Katakana}]]"#
}

private extension String {
    var foldedForMatching: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
