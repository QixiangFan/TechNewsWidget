import NewsKit
import SwiftUI
import WidgetKit

struct NewsWidget: Widget {
    let kind = "NewsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCategoryIntent.self, provider: NewsProvider()) { entry in
            NewsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tech Headlines")
        .description("Latest headlines from tech media, Hacker News and GitHub.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

#Preview("Small", as: .systemSmall) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .chinese, family: .systemSmall, redacted: false)
}

#Preview("Medium", as: .systemMedium) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .all, family: .systemMedium, redacted: false)
}

#Preview("Large", as: .systemLarge) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .github, family: .systemLarge, redacted: false)
}

#Preview("Extra Large", as: .systemExtraLarge) {
    NewsWidget()
} timeline: {
    NewsEntry.sample(for: .all, family: .systemExtraLarge, redacted: false)
}
