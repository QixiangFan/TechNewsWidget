import AppIntents
import NewsKit
import SwiftUI
import WidgetKit

/// Layout for every widget size. Widgets cannot scroll, so each size shows one page
/// of `WidgetFamily.headlinesPerPage` headlines and a button to flip pages.
struct NewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NewsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 6 : 8) {
            header
            if entry.items.isEmpty {
                emptyState
            } else if family == .systemExtraLarge {
                let half = (entry.items.count + 1) / 2
                HStack(alignment: .top, spacing: 16) {
                    column(Array(entry.items.prefix(half)))
                    column(Array(entry.items.dropFirst(half)))
                }
            } else {
                column(entry.items)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(entry.category.localizedTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !isSmall, let fetchedAt = entry.fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if entry.pageCount > 1 {
                Button(intent: NextPageIntent(category: entry.category)) {
                    HStack(spacing: 3) {
                        if !isSmall {
                            Text(verbatim: "\(entry.page + 1)/\(entry.pageCount)")
                                .monospacedDigit()
                        }
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Next Page"))
            }
        }
    }

    // MARK: Headlines

    private func column(_ items: [NewsItem]) -> some View {
        VStack(alignment: .leading, spacing: isSmall ? 6 : 5) {
            ForEach(items) { item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: NewsItem) -> some View {
        Button(intent: OpenArticleIntent(url: item.url, category: entry.category)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title(for: item))
                    .font(titleFont)
                    .lineLimit(titleLines)
                if showsDetail, let detail = item.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Prefixes the outlet's name in its color when the category mixes several sources.
    private func title(for item: NewsItem) -> AttributedString {
        let title = AttributedString(item.title)
        guard entry.category.mixesSources, !isSmall else { return title }
        var source = AttributedString(SourceStyle.name(for: item.sourceID) + "  ")
        source.foregroundColor = SourceStyle.color(for: item.sourceID)
        source.font = titleFont.weight(.semibold)
        return source + title
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No headlines right now", systemImage: "wifi.exclamationmark")
                .font(.footnote.weight(.semibold))
            if !isSmall {
                Text("The widget will try again soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Size-dependent styling

    private var isSmall: Bool { family == .systemSmall }

    /// Hacker News points and GitHub stars/descriptions, when there is room for a second line.
    private var showsDetail: Bool {
        !entry.category.mixesSources && (family == .systemLarge || family == .systemExtraLarge)
    }

    private var titleFont: Font { isSmall ? .caption : .footnote }

    private var titleLines: Int {
        switch family {
        case .systemMedium: 1
        case .systemLarge, .systemExtraLarge: showsDetail ? 1 : 2
        default: 2
        }
    }
}
