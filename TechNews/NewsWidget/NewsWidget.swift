import NewsKit
import SwiftUI
import WidgetKit

struct NewsWidget: Widget {
    let kind = "NewsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCategoryIntent.self, provider: NewsProvider()) { entry in
            NewsWidgetView(entry: entry)
        }
        .configurationDisplayName("Tech Headlines")
        .description("Headlines, summaries and pictures from tech media, Hacker News and GitHub.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // The layouts apply their own margins and let the small widget's photo fill the edges.
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .chinese, style: .rich, family: .systemSmall, redacted: false)
    NewsEntry.sample(for: .chinese, style: .headlines, family: .systemSmall, redacted: false)
}

#Preview("Medium", as: .systemMedium) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .all, style: .rich, family: .systemMedium, redacted: false)
    NewsEntry.sample(for: .all, style: .headlines, family: .systemMedium, redacted: false)
}

#Preview("Large", as: .systemLarge) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .all, style: .rich, family: .systemLarge, redacted: false)
    NewsEntry.sample(for: .github, style: .headlines, family: .systemLarge, redacted: false)
}

#Preview("Extra Large", as: .systemExtraLarge) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .english, style: .rich, family: .systemExtraLarge, redacted: false)
    NewsEntry.sample(for: .all, style: .headlines, family: .systemExtraLarge, redacted: false)
}
