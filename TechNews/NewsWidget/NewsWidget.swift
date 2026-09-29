import SwiftUI
import WidgetKit

// Placeholder widget used to check that the extension is embedded, signed and shows up
// in the widget gallery. Real headlines and per-widget configuration come next.

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

struct NewsWidget: Widget {
    let kind = "NewsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            VStack(spacing: 4) {
                Text("TechNews")
                    .font(.headline)
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("TechNews")
        .description("Latest tech headlines.")
    }
}

#Preview(as: .systemSmall) {
    NewsWidget()
} timeline: {
    PlaceholderEntry(date: .now)
}
