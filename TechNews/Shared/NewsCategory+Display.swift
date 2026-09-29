import NewsKit
import SwiftUI

// Shared by the app and the widget (the Shared folder belongs to both targets).

extension NewsCategory {
    /// Name shown in the app's category picker and the widget header.
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .chinese: "Chinese Media"
        case .english: "English Media"
        case .hackerNews: "Hacker News"
        case .github: "GitHub Trending"
        }
    }

    /// Shorter name for tight spots such as the small widget's header.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .chinese: "Chinese"
        case .english: "English"
        case .hackerNews: "Hacker News"
        case .github: "GitHub"
        }
    }

    /// Hacker News is a ranking and has no pictures, so its stories show their position instead.
    var showsRanks: Bool {
        self == .hackerNews
    }

    /// SF Symbol shown next to the category name.
    var symbolName: String {
        switch self {
        case .all: "newspaper.fill"
        case .chinese: "globe.asia.australia.fill"
        case .english: "globe.americas.fill"
        case .hackerNews: "flame.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Tints the category's symbol, the selected tab and the widget's background wash.
    var accentColor: Color {
        switch self {
        case .all: .indigo
        case .chinese: .red
        case .english: .purple
        case .hackerNews: .orange
        case .github: .indigo
        }
    }

    /// True when headlines come from several outlets, so each row should name its source.
    var mixesSources: Bool {
        NewsSource.sources(for: self).count > 1
    }
}
