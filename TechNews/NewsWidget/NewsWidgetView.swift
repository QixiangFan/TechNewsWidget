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

    /// Changes whenever a different page is shown, which drives the page transition.
    var pageID: String {
        "\(category.rawValue)-\(page)-\(fetchedAt?.timeIntervalSince1970 ?? 0)"
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
                EmptyStateView(isSmall: context.isSmall)
                Spacer(minLength: 0)
            } else {
                page
                    .id(entry.pageID)
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

// MARK: - Header

/// Category, update time, page position and the "next page" button.
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
            Spacer(minLength: 4)
            if entry.pageCount > 1 {
                if !context.isSmall {
                    PageIndicator(page: entry.page, count: entry.pageCount)
                }
                NextPageButton(category: entry.category, onPhoto: onPhoto)
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

struct NextPageButton: View {
    let category: NewsCategory
    var onPhoto = false

    var body: some View {
        Button(intent: NextPageIntent(category: category)) {
            Image(systemName: "chevron.forward")
                .font(.system(size: 9, weight: .heavy))
                .frame(width: 20, height: 20)
                .background(Circle().fill(onPhoto ? AnyShapeStyle(.black.opacity(0.32)) : AnyShapeStyle(.quaternary)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Next Page"))
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
            // Color.clear takes the widget's size, so the cropped photo never stretches the layout.
            Color.clear
                .overlay {
                    Image(nsImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
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

struct EmptyStateView: View {
    let isSmall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No headlines right now", systemImage: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
            if !isSmall {
                Text("The widget will try again soon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
