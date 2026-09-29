import AppKit
import NewsKit
import SwiftUI

// The main window's cards. A click opens the article in the default browser; the context menu
// also copies or shares the link.

/// The first story with a photo, across the full width, its title set on the picture.
struct HeroCard: View {
    let item: NewsItem
    let showsSource: Bool
    var rank: Int?

    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    var body: some View {
        Button {
            openURL(item.url)
        } label: {
            HeroBackdrop(item: item, rank: rank)
                .scaleEffect(isHovered ? 1.025 : 1)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0), location: 0.25),
                        .init(color: .black.opacity(0.35), location: 0.55),
                        .init(color: .black.opacity(0.85), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !showsSource, let detail = item.detail {
                            DetailChips(detail: detail, color: .white, onDark: true)
                        } else {
                            StoryKicker(item: item, showsSource: showsSource, onDark: true, size: 12)
                        }
                        Text(item.title)
                            .font(.system(size: 30, weight: .bold, design: item.headlineDesign))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                        if let summary = item.summary {
                            Text(summary)
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(32)
                }
                .aspectRatio(2.35, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(isHovered ? 0.28 : 0.14), radius: isHovered ? 28 : 16, y: isHovered ? 14 : 8)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .linkPointer()
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isHovered)
        .contextMenu { StoryMenu(item: item) }
    }
}

/// A card in the grid: picture, outlet, title, summary and, for Hacker News and GitHub, their stats.
struct StoryCard: View {
    let item: NewsItem
    let showsSource: Bool
    var rank: Int?
    /// Keeps room for a summary even when this story has none, so cards in a row line up.
    var reservesSummary = true
    /// Keeps room for the stats row (Hacker News, GitHub) for the same reason.
    var reservesDetail = false

    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    var body: some View {
        Button {
            openURL(item.url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CardCover(item: item, rank: rank)
                    .scaleEffect(isHovered ? 1.06 : 1)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                VStack(alignment: .leading, spacing: 7) {
                    StoryKicker(item: item, showsSource: showsSource)
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold,
                                      design: item.artwork == .avatar ? .monospaced : .default))
                        .lineLimit(3, reservesSpace: true)
                    if item.summary != nil || reservesSummary {
                        // An empty string would collapse; a space keeps the reserved lines.
                        Text(item.summary ?? " ")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(3, reservesSpace: true)
                    }
                    if let detail = item.detail {
                        DetailChips(detail: detail, color: SourceStyle.color(for: item.sourceID))
                            .padding(.top, 2)
                    } else if reservesDetail {
                        DetailChips(detail: " ", color: .clear)
                            .hidden()
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 13)
                .padding(.bottom, 15)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.07)))
            .shadow(color: .black.opacity(isHovered ? 0.16 : 0.05), radius: isHovered ? 20 : 6, y: isHovered ? 12 : 2)
            .offset(y: isHovered ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .linkPointer()
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isHovered)
        .contextMenu { StoryMenu(item: item) }
    }
}

// MARK: - Covers

/// The hero's full-width picture. Stories without a photo get a deep gradient in the outlet's
/// color with their avatar, rank or monogram, so the white title stays legible.
struct HeroBackdrop: View {
    let item: NewsItem
    var rank: Int?

    var body: some View {
        let color = SourceStyle.color(for: item.sourceID)
        switch item.artwork {
        case .photo:
            RemoteImage(url: item.imageURL.map { ThumbnailStore.downloadURL(for: $0, width: 1600) }) {
                DeepGradient(color: color)
            }
        case .avatar:
            DeepGradient(color: color)
                .overlay(alignment: .trailing) {
                    RemoteImage(url: item.imageURL) { Circle().fill(.white.opacity(0.2)) }
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                        .padding(.trailing, 64)
                }
        case .monogram:
            DeepGradient(color: color)
                .overlay(alignment: .trailing) {
                    Text(rank.map { "\($0)" } ?? SourceStyle.monogram(for: item.sourceID))
                        .font(.system(size: 260, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(.trailing, 40)
                }
        }
    }
}

/// A card's 16:9 picture: the photo, the avatar on a gradient, the rank, or the monogram.
struct CardCover: View {
    let item: NewsItem
    var rank: Int?

    var body: some View {
        let color = SourceStyle.color(for: item.sourceID)
        switch item.artwork {
        case .photo:
            RemoteImage(url: item.imageURL.map { ThumbnailStore.downloadURL(for: $0, width: 800) }) {
                MonogramTile(sourceID: item.sourceID, cornerRadius: 0)
                    .opacity(0.35)
            }
        case .avatar:
            Rectangle()
                .fill(color.gradient)
                .overlay {
                    RadialGradient(colors: [.white.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 140)
                }
                .overlay {
                    RemoteImage(url: item.imageURL) { Circle().fill(.white.opacity(0.2)) }
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                }
        case .monogram:
            if let rank {
                RankTile(rank: rank, sourceID: item.sourceID, cornerRadius: 0)
            } else {
                MonogramTile(sourceID: item.sourceID, cornerRadius: 0)
            }
        }
    }
}

/// A dark, rich gradient in the outlet's color, for covers that carry white text.
struct DeepGradient: View {
    let color: Color

    var body: some View {
        ZStack {
            color
            LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.55)], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Pieces

/// "● IT之家 · 2 hours ago", or the story's stats where the category has a single outlet.
struct StoryKicker: View {
    let item: NewsItem
    let showsSource: Bool
    var onDark = false
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 6) {
            if showsSource {
                Circle()
                    .fill(onDark ? Color.white : SourceStyle.color(for: item.sourceID))
                    .frame(width: 6, height: 6)
                Text(SourceStyle.name(for: item.sourceID))
                    .fontWeight(.bold)
                    .foregroundStyle(onDark ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            if showsSource || item.detail == nil, let date = item.date {
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(onDark ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .lineLimit(1)
    }
}

/// The detail line as small capsules: "mubi.com" "▲680" "💬352", or "+4,712★" "Python".
/// The first capsule is tinted with the outlet's color.
struct DetailChips: View {
    let detail: String
    let color: Color
    /// White capsules for the hero's dark picture.
    var onDark = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(detail.components(separatedBy: " · ").enumerated()), id: \.offset) { index, part in
                Text(part)
                    .font(.system(size: onDark ? 12 : 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(foreground(isFirst: index == 0))
                    .padding(.horizontal, onDark ? 9 : 7)
                    .padding(.vertical, onDark ? 4 : 3)
                    .background(Capsule().fill(background(isFirst: index == 0)))
            }
        }
        .lineLimit(1)
    }

    private func foreground(isFirst: Bool) -> AnyShapeStyle {
        if onDark { return AnyShapeStyle(.white.opacity(isFirst ? 1 : 0.85)) }
        return isFirst ? AnyShapeStyle(color) : AnyShapeStyle(.secondary)
    }

    private func background(isFirst: Bool) -> AnyShapeStyle {
        if onDark { return AnyShapeStyle(.white.opacity(isFirst ? 0.24 : 0.14)) }
        return isFirst ? AnyShapeStyle(color.opacity(0.12)) : AnyShapeStyle(.quaternary)
    }
}

struct StoryMenu: View {
    let item: NewsItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open in Browser", systemImage: "safari") {
            openURL(item.url)
        }
        Button("Copy Link", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        }
        ShareLink(item: item.url)
    }
}

/// Cards sink slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// The pointing-hand cursor over clickable cards (macOS 15 and later).
    @ViewBuilder
    func linkPointer() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.link)
        } else {
            self
        }
    }
}

extension Color {
    /// The window's background: a cool light gray, or near-black in dark mode.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.098, green: 0.098, blue: 0.106, alpha: 1)
            : NSColor(red: 0.949, green: 0.949, blue: 0.961, alpha: 1)
    })

    /// Cards: white, or a lifted gray in dark mode.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.157, green: 0.157, blue: 0.169, alpha: 1)
            : NSColor.white
    })
}
