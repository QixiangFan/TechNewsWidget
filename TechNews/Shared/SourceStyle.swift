import NewsKit
import SwiftUI

/// A fixed color per outlet so headlines are easy to tell apart at a glance.
enum SourceStyle {
    static func color(for sourceID: String) -> Color {
        switch sourceID {
        case "ithome": .red
        case "sspai": .pink
        case "ifanr": .blue
        case "geekpark": .teal
        case "verge": .purple
        case "techcrunch": .green
        case "ars": .brown
        case "hn": .orange
        case "github": .indigo
        default: .gray
        }
    }

    static func name(for sourceID: String) -> String {
        NewsSource.named(sourceID)?.name ?? sourceID
    }
}

/// Colored dot followed by the outlet's name.
struct SourceLabel: View {
    let sourceID: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SourceStyle.color(for: sourceID))
                .frame(width: 6, height: 6)
            Text(SourceStyle.name(for: sourceID))
        }
    }
}
