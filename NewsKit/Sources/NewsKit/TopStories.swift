import Foundation

/// Picks the most important stories without any AI. A story counts as important when other
/// outlets report the same thing, which shows as titles sharing uncommon words ("World Labs",
/// "GPT-6.1"), also across languages. Being near the top of its own feed and being recent count too.
public enum TopStories {
    /// About the first page of the extra-large widget.
    public static let defaultCount = 6
    /// Stories published this long before the download rank below fresh ones.
    static let staleAge: TimeInterval = 36 * 60 * 60
    /// No source fills more than this many of the top slots.
    static let maxPerSource = 2
    /// Titles that share this many uncommon words report the same thing (see `Story.sharedWords(with:)`).
    static let sharedWordsForSameStory = 2.0
    /// Top stories share fewer words than this, so one event doesn't fill two slots.
    static let sharedWordsForSameTopic = 1.0

    /// Up to `count` stories that other outlets also reported, most important first, one per event.
    /// Returns nothing for a single source, or when no two outlets report the same thing.
    /// `lists` holds each source's stories in the source's own order.
    public static func pick(from lists: [[NewsItem]], now: Date, count: Int = defaultCount) -> [NewsItem] {
        let stories = Story.all(in: lists)
        let coverage = coverage(of: stories)
        let candidates = stories.indices
            .filter { !stories[$0].isDigest && !coverage[$0].isEmpty }
            .map { index in (index, score(stories[index], coveredBy: coverage[index].count, now: now)) }
            // Ties go to the source listed first.
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }

        var picked: [Story] = []
        var perSource: [String: Int] = [:]
        for (index, _) in candidates where picked.count < count {
            let story = stories[index]
            guard perSource[story.item.sourceID, default: 0] < maxPerSource,
                  !picked.contains(where: { $0.sharedWords(with: story) >= sharedWordsForSameTopic }) else {
                continue
            }
            picked.append(story)
            perSource[story.item.sourceID, default: 0] += 1
        }
        return picked.map(\.item)
    }

    /// For each story that other outlets also reported, keyed by `NewsItem.id`, the IDs of those outlets.
    public static func coverage(in lists: [[NewsItem]]) -> [String: Set<String>] {
        let stories = Story.all(in: lists)
        var result: [String: Set<String>] = [:]
        for (story, sources) in zip(stories, coverage(of: stories)) where !sources.isEmpty {
            result[story.item.id, default: []].formUnion(sources)
        }
        return result
    }

    /// `items` with the stories in `ids` first, in that order; the rest keep their order.
    /// IDs that are not in `items` are skipped.
    public static func movedToFront(_ items: [NewsItem], ids: [String]) -> [NewsItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let front = ids.compactMap { byID[$0] }
        let frontIDs = Set(front.map(\.id))
        return front + items.filter { !frontIDs.contains($0.id) }
    }

    // MARK: Scoring

    /// The other outlets reporting the same thing as each story.
    private static func coverage(of stories: [Story]) -> [Set<String>] {
        stories.map { story in
            Set(stories.filter { story.reportsSameThing(as: $0) }.map(\.item.sourceID))
        }
    }

    /// Mostly how many other outlets report it, then how high its own outlet puts it.
    private static func score(_ story: Story, coveredBy outlets: Int, now: Date) -> Double {
        var score = Double(outlets) + 0.5 / Double(1 + story.position)
        if let date = story.item.date, now.timeIntervalSince(date) > staleAge {
            score -= 1
        }
        return score
    }

    // MARK: Titles

    struct Story {
        let item: NewsItem
        /// Position in its own source, from 0.
        let position: Int
        /// A morning roundup and the like: it backs up the stories it mentions but is never picked itself.
        let isDigest: Bool
        /// The title's words that few other titles use.
        var uncommonWords: Set<String> = []

        func reportsSameThing(as other: Story) -> Bool {
            item.sourceID != other.item.sourceID && sharedWords(with: other) >= TopStories.sharedWordsForSameStory
        }

        /// How many uncommon words two titles share. A pair of Chinese characters counts half, since a
        /// three-character word such as 智能体 gives two pairs and pairs such as 美元 are common anyway.
        func sharedWords(with other: Story) -> Double {
            if item.id == other.item.id { return .infinity }
            return uncommonWords.intersection(other.uncommonWords).reduce(0) { total, word in
                total + (word.first?.isASCII == true ? 1 : 0.5)
            }
        }

        /// Every story of `lists`, with the words that appear in only a few of all the titles.
        static func all(in lists: [[NewsItem]]) -> [Story] {
            let nonEmpty = lists.filter { !$0.isEmpty }
            guard Set(nonEmpty.compactMap(\.first?.sourceID)).count >= 2 else { return [] }
            let titles = nonEmpty.flatMap { list in
                list.enumerated().map { position, item in
                    (Story(item: item, position: position, isDigest: TopStories.isDigest(item.title)),
                     TopStories.words(in: item.title))
                }
            }
            var titlesUsing: [String: Int] = [:]
            for (_, words) in titles {
                for word in words { titlesUsing[word, default: 0] += 1 }
            }
            // Words such as "OpenAI" on a busy OpenAI day say too little to tell two stories apart.
            let maxTitles = max(3, titles.count * 6 / 100)
            return titles.map { story, words in
                var story = story
                story.uncommonWords = words.filter { titlesUsing[$0, default: 0] <= maxTitles }
                return story
            }
        }
    }

    /// Latin words and numbers such as "6.1" or "m4", and each pair of neighboring Chinese characters,
    /// since Chinese puts no spaces between words. Common English words and bare numbers are left out.
    static func words(in title: String) -> Set<String> {
        var words = Set<String>()
        var word = ""
        var han: [Character] = []

        func endWord() {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let hasDigit = trimmed.contains(where: \.isNumber)
            if !trimmed.isEmpty, !stopWords.contains(trimmed), !trimmed.allSatisfy(\.isNumber),
               trimmed.count >= 3 || hasDigit {
                words.insert(trimmed)
            }
            word = ""
        }
        func endHan() {
            for index in han.indices.dropLast() {
                words.insert(String(han[index...index + 1]))
            }
            han = []
        }

        for character in title.foldedForMatching.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                endHan()
                word.append(character)
            } else if character == ".", !word.isEmpty {
                word.append(character)
            } else if character.unicodeScalars.allSatisfy(\.properties.isIdeographic) {
                endWord()
                han.append(character)
            } else {
                endWord()
                endHan()
            }
        }
        endWord()
        endHan()
        return words
    }

    static func isDigest(_ title: String) -> Bool {
        title.range(of: #"早报|早知道|日报|周报|晚报|速递|\b(morning|digest|roundup)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "your", "its", "are", "was", "has", "have", "will",
        "not", "but", "you", "how", "what", "why", "who", "new", "says", "say", "said", "after", "into", "about",
        "over", "more", "than", "just", "can", "all", "out", "now", "get", "gets", "when", "their", "they", "his",
        "her", "our", "one", "two", "first", "last", "year", "years", "day", "week", "off", "like", "here",
        "there", "been", "being", "were", "only", "also", "even", "still", "most", "make", "makes", "made", "use",
        "using", "used", "people", "company", "launch", "launches", "launched", "via", "show", "ask", "pdf",
    ]
}
