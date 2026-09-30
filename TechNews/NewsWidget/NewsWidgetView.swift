import AppIntents
import AppKit
import NewsKit
import SwiftUI
import WidgetKit

/// Entry point of the widget's view. Reads WidgetKit's environment once and hands it down,
/// so every layout below is a plain view that also renders outside a widget (previews, tests).
struct NewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: NewsEntry

    var body: some View {
        let context = WidgetContext(family: family, isFullColor: renderingMode == .fullColor && showsBackground)
        WidgetContent(entry: entry, context: context)
            .containerBackground(for: .widget) {
                WidgetBackdrop(entry: entry, context: context)
            }
    }
}

/// What the layouts need to know about where they are drawn.
struct WidgetContext {
    var family: WidgetFamily
    /// False in the vibrant and tinted appearances (e.g. the desktop while another app is active),
    /// where the system desaturates everything and replaces the background. Text is then never
    /// placed over a photo, so it stays legible.
    var isFullColor: Bool

    var isSmall: Bool { family == .systemSmall }
}

extension NewsEntry {
    /// The photo that fills the small widget: only in full color, and only for a real news photo.
    func heroPhoto(in context: WidgetContext) -> NSImage? {
        guard style == .rich, context.isSmall, context.isFullColor,
              let item = items.first, item.artwork == .photo,
              let data = thumbnails[item.id] else {
            return nil
        }
        return NSImage(data: data)
    }

    /// Changes when new headlines arrive, which replaces the whole page strip.
    var contentID: String {
        "\(category.rawValue)-\(fetchedAt?.timeIntervalSince1970 ?? 0)"
    }

    /// Changes whenever a different page is shown, which drives the page animation.
    var pageID: String {
        "\(contentID)-\(position)"
    }
}

/// Header plus the stories of the current page, laid out for the style and size.
struct WidgetContent: View {
    /// The widget draws its own margins (see `contentMarginsDisabled()` in `NewsWidget`): 14 pt, within
    /// the 11–16 pt range of Apple's guidelines, is what lets the medium size fit two stories with summaries.
    static let margin: CGFloat = 14

    let entry: NewsEntry
    let context: WidgetContext

    var body: some View {
        let onPhoto = entry.heroPhoto(in: context) != nil
        VStack(alignment: .leading, spacing: context.isSmall ? 8 : 10) {
            WidgetHeader(entry: entry, context: context, onPhoto: onPhoto)
            if entry.items.isEmpty {
                EmptyStateView(isSmall: context.isSmall, sourcesOff: entry.sourcesOff)
                Spacer(minLength: 0)
            } else {
                PageStrip(position: entry.position) {
                    page
                }
                .id(entry.contentID)
                .transition(.push(from: .trailing))
                .invalidatableContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Self.margin)
        .animation(.smooth(duration: 0.55), value: entry.pageID)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    @ViewBuilder
    private var page: some View {
        switch entry.style {
        case .rich: RichLayout(entry: entry, context: context)
        case .headlines: CompactLayout(entry: entry, context: context)
        }
    }
}

/// The current page between two empty neighbors, one page width to either side. Turning the page
/// moves the strip instead of swapping the page: the pages keep their identity from one timeline
/// entry to the next, so WidgetKit slides them in the direction of the button, also when the
/// pages wrap around, and fades the stories in and out on the way.
///
/// The strip takes exactly the height left under the header. A page that runs long overflows at
/// the bottom instead of making the content taller than the widget, which WidgetKit would then
/// center, pushing the header past the top edge.
struct PageStrip<Page: View>: View {
    let position: Int
    @ViewBuilder let page: Page

    var body: some View {
        GeometryReader { proxy in
            ForEach(position - 1 ... position + 1, id: \.self) { slot in
                Group {
                    if slot == position {
                        page
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .offset(x: CGFloat(slot - position) * proxy.size.width)
            }
        }
    }
}

// MARK: - Header

/// Category, update time, page position and the page buttons.
struct WidgetHeader: View {
    let entry: NewsEntry
    let context: WidgetContext
    /// White text for the small widget's photo background.
    var onPhoto = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.category.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(onPhoto ? .white : entry.category.accentColor)
                .widgetAccentable()
            Text(context.isSmall ? entry.category.shortTitle : entry.category.localizedTitle)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            if !context.isSmall, let fetchedAt = entry.fetchedAt {
                Text(fetchedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))"))
            }
            // The stack's spacing already leaves 10 pt around the spacer; an extra minimum would
            // cut "Hacker News" short next to the page buttons in the small widget.
            Spacer(minLength: 0)
            if entry.pageCount > 1 {
                if !context.isSmall {
                    PageIndicator(page: entry.page, count: entry.pageCount)
                }
                PageButtons(category: entry.category, onPhoto: onPhoto)
            }
        }
        .foregroundStyle(onPhoto ? .white : .primary)
        .shadow(color: onPhoto ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
    }
}

/// Elongated dots for a few pages, a progress bar with a counter for many.
struct PageIndicator: View {
    let page: Int
    let count: Int

    var body: some View {
        Group {
            if count <= 6 {
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                            .frame(width: index == page ? 10 : 4, height: 4)
                    }
                }
            } else {
                HStack(spacing: 5) {
                    Text(verbatim: "\(page + 1)/\(count)")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(page)))
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 28, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.secondary)
                                .frame(width: max(4, 28 * CGFloat(page + 1) / CGFloat(count)), height: 3)
                        }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(page + 1) of \(count)"))
    }
}

/// Previous and next page in one capsule, like the back and forward buttons of a Mac toolbar.
struct PageButtons: View {
    let category: NewsCategory
    var onPhoto = false

    var body: some View {
        HStack(spacing: 0) {
            button(PreviousPageIntent(category: category), symbol: "chevron.backward", label: "Previous Page")
            button(NextPageIntent(category: category), symbol: "chevron.forward", label: "Next Page")
        }
        .background(Capsule().fill(onPhoto ? AnyShapeStyle(.black.opacity(0.32)) : AnyShapeStyle(.quaternary)))
    }

    private func button(_ intent: some AppIntent, symbol: String, label: LocalizedStringResource) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Background and empty state

/// The widget's background: a sheet of paper washed with the category's color, or, for the
/// small widget's lead story, the photo itself under a darkening gradient.
struct WidgetBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: NewsEntry
    let context: WidgetContext

    var body: some View {
        if let photo = entry.heroPhoto(in: context) {
            FilledImage(image: photo)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.5), location: 0),
                        .init(color: .black.opacity(0), location: 0.32),
                        .init(color: .black.opacity(0.05), location: 0.42),
                        .init(color: .black.opacity(0.82), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
        } else {
            ZStack {
                // Near-white or deep gray: softer than pure white or black.
                colorScheme == .dark
                    ? Color(red: 0.110, green: 0.110, blue: 0.122)
                    : Color(red: 0.992, green: 0.992, blue: 0.996)
                LinearGradient(colors: [entry.category.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.13), .clear],
                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 0.8))
            }
        }
    }
}

/// No stories: the download failed, or every source of the category is turned off in the app's settings.
struct EmptyStateView: View {
    let isSmall: Bool
    var sourcesOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(sourcesOff ? "Sources turned off" : "No headlines right now",
                  systemImage: sourcesOff ? "eye.slash" : "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
            if !isSmall {
                Text(sourcesOff ? "Turn them on in TechNews Settings." : "The widget will try again soon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
