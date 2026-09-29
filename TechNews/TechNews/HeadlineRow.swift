import NewsKit
import SwiftUI

/// One headline in the main window. Clicking it opens the article in the default browser.
struct HeadlineRow: View {
    let item: NewsItem
    let showsSource: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(item.url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if showsSource {
                        SourceLabel(sourceID: item.sourceID)
                    }
                    if let detail = item.detail {
                        Text(detail)
                            .lineLimit(1)
                    }
                    if let date = item.date {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.url.absoluteString)
    }
}
