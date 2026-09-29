import Foundation

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom feeds into `NewsItem`s.
/// Only the title, link, date, summary and lead image of each entry are read; everything else is skipped.
final class FeedParser: NSObject, XMLParserDelegate {
    private let source: NewsSource
    private var items: [NewsItem] = []

    private var depth = 0
    /// Depth of the `<item>` / `<entry>` currently being read, or nil when outside one.
    private var entryDepth: Int?
    private var text = ""
    private var entry = Entry()

    /// What has been read so far from the current `<item>` / `<entry>`.
    private struct Entry {
        var title: String?
        var link: String?
        var published: String?
        var updated: String?
        /// `<description>` (RSS) or `<summary>` (Atom), usually HTML.
        var summary: String?
        /// The full article (`<content:encoded>` or Atom `<content>`). Only used to find the lead
        /// image, or as the summary when there is no description; it is never stored.
        var content: String?
        /// `url` of `<media:content>` / `<media:thumbnail>`.
        var mediaImage: String?
        /// `url` of an image `<enclosure>`.
        var enclosureImage: String?
        /// Text of a plain `<image>` element (爱范儿).
        var plainImage: String?

        /// The first usable image, preferring ones the feed marks as the lead image
        /// over the `<img>` tags in the summary or article.
        func imageURL(relativeTo articleURL: URL) -> URL? {
            for candidate in [mediaImage, enclosureImage, plainImage].compactMap({ $0 }) {
                if let url = FeedImage.url(from: candidate, relativeTo: articleURL) { return url }
            }
            for html in [summary, content].compactMap({ $0 }) {
                if let url = FeedImage.firstImage(inHTML: html, relativeTo: articleURL) { return url }
            }
            return nil
        }
    }

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
            entry = Entry()
        } else if let entryDepth, depth == entryDepth + 1 {
            text = ""
            switch elementName {
            case "link":
                // Atom: <link rel="alternate" href="..."/>; a missing rel means alternate.
                if entry.link == nil, let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" {
                    entry.link = href
                }
            case "media:content", "media:thumbnail":
                // <media:thumbnail> has neither attribute and is always an image.
                let isImage = attributes["medium"].map { $0 == "image" }
                    ?? attributes["type"].map { $0.hasPrefix("image/") }
                    ?? true
                if entry.mediaImage == nil, isImage {
                    entry.mediaImage = attributes["url"]
                }
            case "enclosure":
                if entry.enclosureImage == nil, attributes["type"]?.hasPrefix("image/") == true {
                    entry.enclosureImage = attributes["url"]
                }
            default:
                break
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
            case "title": entry.title = value
            case "link" where entry.link == nil && !value.isEmpty: entry.link = value
            case "pubDate", "published", "dc:date": entry.published = value
            case "updated": entry.updated = value
            case "description", "summary":
                if entry.summary == nil { entry.summary = value.nonEmpty }
            case "content:encoded", "content":
                if entry.content == nil { entry.content = value.nonEmpty }
            case "image": entry.plainImage = value.nonEmpty
            default: break
            }
        } else if depth == entryDepth {
            self.entryDepth = nil
            if let title = entry.title, !title.isEmpty,
               let link = entry.link, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) {
                items.append(NewsItem(
                    title: title,
                    url: url,
                    sourceID: source.id,
                    date: FeedDate.parse(entry.published ?? entry.updated),
                    summary: entry.summary ?? entry.content,
                    imageURL: entry.imageURL(relativeTo: url)
                ))
            }
        }
    }
}

/// Picks usable image addresses out of feed markup.
enum FeedImage {
    private static let imgSource = try! NSRegularExpression(
        pattern: #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)

    /// The first `<img>` in `html` that makes a usable thumbnail.
    static func firstImage(inHTML html: String, relativeTo articleURL: URL) -> URL? {
        for match in imgSource.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let range = Range(match.range(at: 1), in: html),
               let url = url(from: String(html[range]), relativeTo: articleURL) {
                return url
            }
        }
        return nil
    }

    /// Resolves `string` against the article's address and rejects what makes a poor thumbnail:
    /// inline `data:` images, animated GIFs (usually tracking pixels), SVGs and emoji.
    static func url(from string: String, relativeTo articleURL: URL) -> URL? {
        let trimmed = string.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed, relativeTo: articleURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        let path = url.path.lowercased()
        if path.hasSuffix(".gif") || path.hasSuffix(".svg") || path.contains("/emoji/") {
            return nil
        }
        return url
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
