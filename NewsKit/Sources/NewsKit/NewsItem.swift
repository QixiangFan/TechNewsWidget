import Foundation

/// A single headline. Only the fields needed to render one row are stored,
/// so the on-disk cache stays small (see `CacheLimits`).
public struct NewsItem: Codable, Hashable, Identifiable, Sendable {
    public let title: String
    public let url: URL
    public let sourceID: String
    public let date: Date?
    /// Short secondary line, e.g. a GitHub repo description or Hacker News points.
    public let detail: String?

    public var id: String { url.absoluteString }

    public var source: NewsSource? { NewsSource.named(sourceID) }

    public init(title: String, url: URL, sourceID: String, date: Date? = nil, detail: String? = nil) {
        self.title = title.cleanedText(maxLength: CacheLimits.maxTitleLength)
        self.url = url
        self.sourceID = sourceID
        self.date = date
        let cleanedDetail = detail?.cleanedText(maxLength: CacheLimits.maxDetailLength)
        self.detail = (cleanedDetail?.isEmpty ?? true) ? nil : cleanedDetail
    }

    // Single-letter keys keep the cached JSON compact.
    private enum CodingKeys: String, CodingKey {
        case title = "t"
        case url = "u"
        case sourceID = "s"
        case date = "d"
        case detail = "x"
    }
}
