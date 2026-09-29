import NewsKit
import SwiftUI

// Presentation helpers shared by the app and the widget.

extension NewsItem {
    /// What the item's picture shows, which decides how it is framed.
    enum Artwork {
        /// A news photo, cropped to fill.
        case photo
        /// A GitHub owner's avatar, shown whole in a circle.
        case avatar
        /// No picture: the outlet's `MonogramTile` stands in.
        case monogram
    }

    var artwork: Artwork {
        guard imageURL != nil else { return .monogram }
        return source?.kind == .githubTrending ? .avatar : .photo
    }

    /// "mubi.com" for a Hacker News link, used where the story has no picture.
    var domain: String? {
        guard let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// True when the title contains Chinese or Japanese characters.
    var hasCJKTitle: Bool {
        title.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    /// The display face for a prominent headline: monospaced for a GitHub repository name, New York
    /// for Latin text, the system face for Chinese (a serif Latin face next to the sans-serif Chinese
    /// fallback in one line looks uneven).
    var headlineDesign: Font.Design {
        if source?.kind == .githubTrending { return .monospaced }
        return hasCJKTitle ? .default : .serif
    }
}

extension Date {
    /// "18:08" for today, "Sep 28" / "9月28日" for earlier days. Always correct, unlike
    /// "2 hours ago", which would go stale between widget refreshes.
    func newsTimestamp(now: Date = .now) -> String {
        if Calendar.current.isDate(self, inSameDayAs: now) {
            return formatted(date: .omitted, time: .shortened)
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
