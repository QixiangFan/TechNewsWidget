import AppIntents
import NewsKit
import SwiftUI
import WidgetKit

/// "Headlines Only": as many titles as fit, two columns on the extra-large size.
struct CompactLayout: View {
    let entry: NewsEntry
    let context: WidgetContext

    var body: some View {
        if context.family == .systemExtraLarge {
            let half = (entry.items.count + 1) / 2
            HStack(alignment: .top, spacing: 18) {
                column(Array(entry.items.prefix(half)))
                column(Array(entry.items.dropFirst(half)))
            }
        } else {
            column(entry.items)
        }
    }

    private func column(_ items: [NewsItem]) -> some View {
        VStack(alignment: .leading, spacing: context.isSmall ? 7 : 6) {
            ForEach(items) { item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ item: NewsItem) -> some View {
        Button(intent: OpenArticleIntent(url: item.url, category: entry.category)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title(for: item))
                    .font(titleFont)
                    .lineLimit(titleLines)
                if showsDetail, let detail = [item.detail, item.summary].compactMap({ $0 }).joined(separator: " · ").nonEmpty {
                    Text(detail)
                        .font(.system(size: 10))
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
        guard entry.category.mixesSources, !context.isSmall else { return title }
        var source = AttributedString(SourceStyle.name(for: item.sourceID) + "  ")
        source.foregroundColor = SourceStyle.color(for: item.sourceID)
        source.font = titleFont.weight(.bold)
        return source + title
    }

    /// Hacker News points and GitHub stars/descriptions under the title, except on the medium
    /// size, which shows more single-line titles instead.
    private var showsDetail: Bool {
        !entry.category.mixesSources && context.family != .systemMedium
    }

    private var titleFont: Font {
        .system(size: context.isSmall ? 11 : 11.5, weight: .medium)
    }

    private var titleLines: Int {
        showsDetail || context.family == .systemMedium ? 1 : 2
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
