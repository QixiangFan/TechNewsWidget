import AppIntents
import AppKit
import NewsKit

/// Category choices shown when the user edits a widget.
enum CategoryOption: String, AppEnum {
    case all
    case chinese
    case english
    case hackerNews
    case github

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "All",
        .chinese: "Chinese Media",
        .english: "English Media",
        .hackerNews: "Hacker News",
        .github: "GitHub Trending",
    ]

    init(_ category: NewsCategory) {
        self = CategoryOption(rawValue: category.rawValue) ?? .all
    }

    var newsCategory: NewsCategory {
        NewsCategory(rawValue: rawValue) ?? .all
    }
}

/// How much of each story the widget shows.
enum StyleOption: String, AppEnum {
    /// Pictures, summaries and a lead story; fewer stories per page.
    case rich
    /// Titles only, as many as fit.
    case headlines

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Style")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .rich: "Headlines & Images",
        .headlines: "Headlines Only",
    ]
}

/// Per-widget configuration: which category of headlines to show, and how.
struct SelectCategoryIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Category" }
    static var description: IntentDescription { "Choose which headlines this widget shows." }

    @Parameter(title: "Category", default: .all)
    var category: CategoryOption

    @Parameter(title: "Style", default: .rich)
    var style: StyleOption
}

/// The "next page" button in the widget header. Runs inside the widget extension,
/// after which WidgetKit reloads the timeline and `NewsProvider` shows the next page.
struct NextPageIntent: AppIntent {
    static var title: LocalizedStringResource { "Next Page" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Category")
    var category: CategoryOption

    init() {}

    init(category: NewsCategory) {
        self.category = CategoryOption(category)
    }

    func perform() async throws -> some IntentResult {
        PageStore.turn(category.newsCategory, by: 1)
        return .result()
    }
}

/// The "previous page" button next to it; from the first page it goes to the last.
struct PreviousPageIntent: AppIntent {
    static var title: LocalizedStringResource { "Previous Page" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Category")
    var category: CategoryOption

    init() {}

    init(category: NewsCategory) {
        self.category = CategoryOption(category)
    }

    func perform() async throws -> some IntentResult {
        PageStore.turn(category.newsCategory, by: -1)
        return .result()
    }
}

/// Tapping a headline. A plain `Link` in a macOS widget activates the containing app first,
/// so the widget extension opens the article in the default browser itself.
struct OpenArticleIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Article" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Link")
    var url: URL

    @Parameter(title: "Category")
    var category: CategoryOption

    init() {}

    init(url: URL, category: NewsCategory) {
        self.url = url
        self.category = CategoryOption(category)
    }

    func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget after any button; keep the current page and skip downloading.
        PageStore.reuseCacheOnce(category.newsCategory)
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
        return .result()
    }
}
