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

    /// True when headlines come from several outlets, so each row should name its source.
    var mixesSources: Bool {
        NewsSource.sources(for: self).count > 1
    }
}
