import Foundation

/// A single headline. Only the fields needed to render one row are stored,
/// so the on-disk cache stays small (see `CacheLimits`).
public struct NewsItem: Codable, Hashable, Identifiable, Sendable {
    public let title: String
    public let url: URL
    public let sourceID: String
    public let date: Date?
    /// Short secondary line, e.g. Hacker News points or GitHub stars and language.
    public let detail: String?
    /// The outlet's own summary or opening lines (never AI-generated), shortened for display.
    public let summary: String?
    /// The article's lead image. Only this address is cached with the headline; the image itself
    /// is downloaded as a small thumbnail by `ThumbnailStore`.
    public let imageURL: URL?

    public var id: String { url.absoluteString }

    public var source: NewsSource? { NewsSource.named(sourceID) }

    public init(title: String, url: URL, sourceID: String, date: Date? = nil, detail: String? = nil,
                summary: String? = nil, imageURL: URL? = nil) {
        let fullTitle = title.plainText()
        self.title = fullTitle.truncated(to: CacheLimits.maxTitleLength)
        self.url = url
        self.sourceID = sourceID
        self.date = date
        self.detail = detail?.cleanedText(maxLength: CacheLimits.maxDetailLength).nonEmpty
        self.summary = summary?.summaryText(maxLength: CacheLimits.maxSummaryLength, droppingTitle: fullTitle).nonEmpty
        self.imageURL = imageURL
    }

    // Single-letter keys keep the cached JSON compact. Caches written before `summary` and
    // `imageURL` existed still decode; those fields are simply nil.
    private enum CodingKeys: String, CodingKey {
        case title = "t"
        case url = "u"
        case sourceID = "s"
        case date = "d"
        case detail = "x"
        case summary = "m"
        case imageURL = "i"
    }
}
