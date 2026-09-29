import Foundation

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom feeds into `NewsItem`s.
/// Only the title, link and date of each entry are read; everything else is skipped.
final class FeedParser: NSObject, XMLParserDelegate {
    private let source: NewsSource
    private var items: [NewsItem] = []

    private var depth = 0
    /// Depth of the `<item>` / `<entry>` currently being read, or nil when outside one.
    private var entryDepth: Int?
    private var text = ""
    private var title: String?
    private var link: String?
    private var published: String?
    private var updated: String?

    private init(source: NewsSource) {
        self.source = source
    }

    static func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        let delegate = FeedParser(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let succeeded = parser.parse()
        // Some feeds have trailing junk, so keep whatever parsed before an error. No entries at all
        // (e.g. an anti-bot HTML page served instead of the feed) counts as a failure.
        guard !delegate.items.isEmpty else {
            let reason = succeeded ? "no entries found" : parser.parserError?.localizedDescription ?? "unknown error"
            throw NewsError.unreadableFeed(source.id, reason)
        }
        return delegate.items
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if elementName == "item" || elementName == "entry" {
            entryDepth = depth
            title = nil
            link = nil
            published = nil
            updated = nil
        } else if let entryDepth, depth == entryDepth + 1 {
            text = ""
            // Atom: <link rel="alternate" href="..."/>; a missing rel means alternate.
            if elementName == "link", link == nil, let href = attributes["href"],
               (attributes["rel"] ?? "alternate") == "alternate" {
                link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if entryDepth != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if entryDepth != nil, let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        defer { depth -= 1 }
        guard let entryDepth else { return }

        if depth == entryDepth + 1 {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "title": title = value
            case "link" where link == nil && !value.isEmpty: link = value
            case "pubDate", "published", "dc:date": published = value
            case "updated": updated = value
            default: break
            }
        } else if depth == entryDepth {
            self.entryDepth = nil
            if let title, !title.isEmpty,
               let link, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let date = FeedDate.parse(published ?? updated)
                items.append(NewsItem(title: title, url: url, sourceID: source.id, date: date))
            }
        }
    }
}

/// Date parsing for the formats seen in real feeds (RFC 822 and ISO 8601).
enum FeedDate {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let rfc822: [DateFormatter] = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func parse(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if let date = iso8601.date(from: string) ?? iso8601Fractional.date(from: string) {
            return date
        }
        for formatter in rfc822 {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
