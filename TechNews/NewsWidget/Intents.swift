import AppIntents
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

/// Per-widget configuration: which category of headlines to show.
struct SelectCategoryIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Category" }
    static var description: IntentDescription { "Choose which headlines this widget shows." }

    @Parameter(title: "Category", default: .all)
    var category: CategoryOption
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
        PageStore.advance(category.newsCategory)
        return .result()
    }
}
