import AppIntents
import AppKit
import NewsKit
import SwiftUI
import WidgetKit

/// "Headlines & Images": pictures, summaries and, on the large sizes, a lead story.
///
/// Every size is laid out for the macOS widget sizes: small 164 × 164 pt, medium 344 × 164,
/// large 344 × 344, extra large 704 × 344. After the 14 pt margins and the header (20 pt plus
/// 10 pt of spacing), the stories get 316 × 106 on the medium size and 286 pt of height on the
/// large ones. Rows have fixed heights that add up to that; the lead story's picture takes what is left.
struct RichLayout: View {
    let entry: NewsEntry
    let context: WidgetContext

    var body: some View {
        let stories = entry.items.enumerated().map { Story(item: $1, rank: rank(at: $0)) }
        switch context.family {
        case .systemSmall:
            if let story = stories.first {
                SmallStory(story: story, entry: entry, context: context)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                if let lead = stories.first {
                    // Three rows leave the lead about 124 pt: enough for its photo and title, not a summary.
                    LeadStory(story: lead, entry: entry, context: context, titleSize: 14, summaryLines: 0)
                }
                Hairline()
                rows(stories.dropFirst(), artwork: CGSize(width: 56, height: 42), titleSize: 11.5, spacing: 8)
            }
        case .systemExtraLarge:
            // Two equal columns, each about as wide as the large size.
            HStack(alignment: .top, spacing: 18) {
                if let lead = stories.first {
                    LeadStory(story: lead, entry: entry, context: context, titleSize: 17, summaryLines: 4)
                        .frame(maxWidth: .infinity)
                }
                rows(stories.dropFirst(), artwork: CGSize(width: 85, height: 64), titleSize: 12, spacing: 10)
            }
        default:
            rows(stories[...], artwork: CGSize(width: 65, height: 49), titleSize: 11.5, spacing: 8)
        }
    }

    private func rows(_ stories: ArraySlice<Story>, artwork: CGSize, titleSize: CGFloat,
                      spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(stories) { story in
                RichRow(story: story, entry: entry, artworkSize: artwork, titleSize: titleSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Position in the whole ranking, counting the pages before this one.
    private func rank(at index: Int) -> Int? {
        guard entry.category.showsRanks else { return nil }
        return entry.page * context.family.headlinesPerPage(style: .rich) + index + 1
    }
}

/// An item with its position in a ranked category.
struct Story: Identifiable {
    let item: NewsItem
    let rank: Int?

    var id: String { item.id }
}

// MARK: - Stories

/// The small widget's single story: over its photo in full color, otherwise a byline and a title
/// set as large as it fits, with the summary filling what is left.
struct SmallStory: View {
    let story: Story
    let entry: NewsEntry
    let context: WidgetContext

    private var item: NewsItem { story.item }

    var body: some View {
        Button(intent: OpenArticleIntent(url: item.url, category: entry.category)) {
            Group {
                if entry.heroPhoto(in: context) != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)
                        Kicker(item: item, onPhoto: true)
                        // Short titles are set larger; the photo keeps at least the top half.
                        ViewThatFits(in: .vertical) {
                            photoTitle(size: 16, lineLimit: nil)
                            photoTitle(size: 14.5, lineLimit: nil)
                            photoTitle(size: 13.5, lineLimit: 3)
                        }
                        .frame(maxHeight: 66, alignment: .bottomLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            WidgetArtwork(item: item, data: entry.thumbnails[item.id], rank: story.rank,
                                          cornerRadius: 9)
                                .frame(width: 38, height: 38)
                            Byline(item: item, showsSource: entry.category.mixesSources)
                        }
                        ViewThatFits(in: .vertical) {
                            storyText(titleSize: 17, summaryLines: 3)
                            storyText(titleSize: 15, summaryLines: 2)
                            storyText(titleSize: 13.5, summaryLines: 1)
                            storyText(titleSize: 13, summaryLines: 0, titleLimit: 4)
                        }
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func photoTitle(size: CGFloat, lineLimit: Int?) -> some View {
        Text(item.title)
            .font(.system(size: size, weight: .bold, design: item.headlineDesign))
            .foregroundStyle(.white)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }

    /// Titles without a line limit only fit when shown whole, so `ViewThatFits` picks the largest
    /// size that needs no ellipsis; the last variant is the fallback that truncates.
    private func storyText(titleSize: CGFloat, summaryLines: Int, titleLimit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: titleSize, weight: .semibold, design: item.headlineDesign))
                .lineLimit(titleLimit)
                .fixedSize(horizontal: false, vertical: true)
            if summaryLines > 0, let summary = item.summary {
                Text(summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(summaryLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The large sizes' lead story. In full color its title sits on the photo, like a magazine cover;
/// in the tinted and vibrant appearances the picture becomes a banner above the text.
/// Either way the picture fills the height the text leaves free.
struct LeadStory: View {
    let story: Story
    let entry: NewsEntry
    let context: WidgetContext
    let titleSize: CGFloat
    /// Lines of summary under the picture; 0 for none.
    let summaryLines: Int

    private var item: NewsItem { story.item }

    var body: some View {
        Button(intent: OpenArticleIntent(url: item.url, category: entry.category)) {
            VStack(alignment: .leading, spacing: 7) {
                if context.isFullColor, item.artwork == .photo, let photo {
                    cover(photo)
                        .frame(maxHeight: .infinity)
                } else {
                    WidgetArtwork(item: item, data: entry.thumbnails[item.id], rank: story.rank, cornerRadius: 10)
                        .frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(item: item, showsSource: entry.category.mixesSources)
                        title.foregroundStyle(.primary)
                    }
                }
                if summaryLines > 0, let summary = item.summary {
                    Text(summary)
                        .font(.system(size: titleSize - 3))
                        .foregroundStyle(.secondary)
                        .lineLimit(summaryLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var photo: NSImage? {
        entry.thumbnails[item.id].flatMap(NSImage.init(data:))
    }

    private var title: some View {
        Text(item.title)
            .font(.system(size: titleSize, weight: .bold, design: item.headlineDesign))
            .lineLimit(2)
    }

    private func cover(_ photo: NSImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return FilledImage(image: photo)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0.3),
                    .init(color: .black.opacity(0.8), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(item: item, showsSource: entry.category.mixesSources, onPhoto: true)
                    title
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 10)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Picture on the left; outlet, title and as much of the summary as fits on the right.
struct RichRow: View {
    let story: Story
    let entry: NewsEntry
    let artworkSize: CGSize
    var titleSize: CGFloat = 12

    private var item: NewsItem { story.item }

    var body: some View {
        Button(intent: OpenArticleIntent(url: item.url, category: entry.category)) {
            HStack(alignment: .top, spacing: 10) {
                WidgetArtwork(item: item, data: entry.thumbnails[item.id], rank: story.rank, cornerRadius: 7)
                    .frame(width: artworkSize.width, height: artworkSize.height)
                // The first variant that fits the row's height wins, so a short title leaves room
                // for two lines of summary and a long one for none.
                ViewThatFits(in: .vertical) {
                    text(summaryLines: 2)
                    text(summaryLines: 1)
                    text(summaryLines: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: artworkSize.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func text(summaryLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(item: item, showsSource: entry.category.mixesSources)
            Text(item.title)
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if summaryLines > 0, let summary = item.summary {
                Text(summary)
                    .font(.system(size: titleSize - 1.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(summaryLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pieces

/// "● IT之家  18:08": the outlet when the category mixes several, then the detail line
/// (Hacker News points, GitHub stars) or the time.
struct Kicker: View {
    let item: NewsItem
    var showsSource = true
    /// White text for a photo background.
    var onPhoto = false

    var body: some View {
        HStack(spacing: 4) {
            if showsSource {
                Circle()
                    .fill(onPhoto ? Color.white : SourceStyle.color(for: item.sourceID))
                    .frame(width: 5, height: 5)
                    .widgetAccentable()
                Text(SourceStyle.name(for: item.sourceID))
                    .fontWeight(.bold)
                    .foregroundStyle(onPhoto ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            if let meta = item.detail ?? item.date?.newsTimestamp() {
                Text(meta)
                    .foregroundStyle(onPhoto ? AnyShapeStyle(.white.opacity(0.78)) : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .lineLimit(1)
    }
}

/// Two lines next to the small widget's picture: the outlet and the time, or, when the
/// category has a single outlet, the item's detail ("mubi.com" over "▲680 · 💬352").
struct Byline: View {
    let item: NewsItem
    let showsSource: Bool

    var body: some View {
        let meta = item.detail ?? item.date?.newsTimestamp() ?? ""
        let parts = meta.components(separatedBy: " · ")
        let lines = showsSource
            ? [SourceStyle.name(for: item.sourceID), meta]
            : [parts[0], parts.dropFirst().joined(separator: " · ")]
        VStack(alignment: .leading, spacing: 1) {
            Text(lines[0])
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SourceStyle.color(for: item.sourceID))
                .widgetAccentable()
            if !lines[1].isEmpty {
                Text(lines[1])
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// The story's picture: a cropped photo, an avatar on a tinted plate, its rank, or the outlet's monogram.
struct WidgetArtwork: View {
    let item: NewsItem
    let data: Data?
    var rank: Int? = nil
    var cornerRadius: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let image = data.flatMap(NSImage.init(data:)) {
            if item.artwork == .avatar {
                shape
                    .fill(SourceStyle.color(for: item.sourceID).opacity(0.14))
                    .overlay {
                        FilledImage(image: image)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                            .padding(5)
                    }
            } else {
                FilledImage(image: image)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            }
        } else if let rank {
            RankTile(rank: rank, sourceID: item.sourceID, cornerRadius: cornerRadius)
        } else {
            MonogramTile(sourceID: item.sourceID, cornerRadius: cornerRadius)
        }
    }
}

/// A picture cropped to fill its frame.
///
/// `.scaledToFill()` would lay the image out larger than its frame and only clip what is drawn,
/// but on the desktop WidgetKit treats the whole image as being under the pointer: the large
/// widget's lead photo reached up over the header, so clicking the page buttons opened the app
/// instead. Cropping the bitmap to the frame's shape keeps the image exactly the size of its frame.
struct FilledImage: View {
    let image: NSImage

    var body: some View {
        GeometryReader { proxy in
            Image(nsImage: image.cropped(toAspectRatioOf: proxy.size))
                .resizable()
                .desaturatedInTintedAppearance()
        }
    }
}

private extension NSImage {
    /// The centered part of the image that has the aspect ratio of `size`.
    func cropped(toAspectRatioOf size: CGSize) -> NSImage {
        guard size.width > 0, size.height > 0,
              let bitmap = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let width = CGFloat(bitmap.width)
        let height = CGFloat(bitmap.height)
        let aspectRatio = size.width / size.height
        let crop = width / height > aspectRatio
            ? CGRect(x: (width - height * aspectRatio) / 2, y: 0, width: height * aspectRatio, height: height)
            : CGRect(x: 0, y: (height - width / aspectRatio) / 2, width: width, height: width / aspectRatio)
        guard let cropped = bitmap.cropping(to: crop.integral) else { return self }
        return NSImage(cgImage: cropped, size: .zero)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 0.5)
    }
}

extension Image {
    /// Keeps photos recognizable in the tinted and clear widget appearances (macOS 15 and later)
    /// instead of letting the system flatten them into the tint color.
    @ViewBuilder
    func desaturatedInTintedAppearance() -> some View {
        if #available(macOS 15.0, *) {
            widgetAccentedRenderingMode(.desaturated)
        } else {
            self
        }
    }
}
