import NewsKit
import SwiftUI

/// The visual identity of each outlet: a fixed color and a short monogram, so stories are easy
/// to tell apart at a glance and stories without a picture still get recognizable artwork.
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

    /// One to three characters that stand in for the outlet's logo.
    static func monogram(for sourceID: String) -> String {
        switch sourceID {
        case "ithome": "IT"
        case "sspai": "少"
        case "ifanr": "爱"
        case "geekpark": "极"
        case "verge": "V"
        case "techcrunch": "TC"
        case "ars": "ars"
        case "hn": "Y"
        case "github": "GH"
        default: String(name(for: sourceID).prefix(2))
        }
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

/// Stand-in artwork for stories without a picture: the outlet's monogram on its color,
/// lit from the top left like an app icon. Large tiles also spell out the outlet's name.
struct MonogramTile: View {
    let sourceID: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        let color = SourceStyle.color(for: sourceID)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let isLarge = proxy.size.width >= 140 && proxy.size.height >= 90
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading,
                                             startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height)))
                }
                .overlay {
                    VStack(spacing: 2) {
                        Text(SourceStyle.monogram(for: sourceID))
                            .font(.system(size: min(side * 0.42, 40), weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.4)
                        if isLarge {
                            Text(SourceStyle.name(for: sourceID))
                                .font(.system(size: 12, weight: .semibold))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(side * 0.12)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
        }
        .accessibilityHidden(true)
    }
}

/// A story's position in a ranking such as the Hacker News front page, set in the outlet's color.
struct RankTile: View {
    let rank: Int
    let sourceID: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        let color = SourceStyle.color(for: sourceID)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.opacity(0.14))
                .overlay {
                    Text(rank, format: .number)
                        .font(.system(size: min(side * 0.56, 110), weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color.gradient)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(side * 0.08)
                }
        }
        .accessibilityHidden(true)
    }
}
