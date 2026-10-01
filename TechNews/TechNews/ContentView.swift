import NewsKit
import SwiftUI

/// Main window: a magazine front page for the selected category, with a masthead, category tabs
/// that stay pinned while scrolling, a hero story and a grid of cards. Refresh also reloads the widgets.
/// The most important stories come first unless Settings ask for one source after another.
/// Stories that mention a muted word are left out, and headlines are downloaded again after the
/// refresh interval chosen in Settings.
struct ContentView: View {
    @AppStorage(NewsSettings.Key.mutedWords, store: AppGroup.defaults) private var mutedWords = ""
    @AppStorage(NewsSettings.Key.refreshInterval, store: AppGroup.defaults) private var refreshInterval = RefreshInterval.standard
    @AppStorage(NewsSettings.Key.storyOrder, store: AppGroup.defaults) private var storyOrder = StoryOrder.standard
    @State private var category: NewsCategory = .all
    @State private var results: [NewsCategory: LoadedNews] = [:]
    @State private var loadingCategory: NewsCategory?
    /// The category whose cards have played their entrance animation.
    @State private var revealedCategory: NewsCategory?

    private let service = NewsService()
    private static let margin: CGFloat = 32
    private static let topID = "top"
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Masthead()
                        .padding(.horizontal, Self.margin)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .id(Self.topID)
                    Section {
                        content
                            .padding(.horizontal, Self.margin)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    } header: {
                        CategoryBar(selection: $category)
                            .padding(.horizontal, Self.margin - 6)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.canvas.opacity(0.88))
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .onChange(of: category) {
                withAnimation(.smooth) {
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { refreshButton }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .task(id: category) {
            if results[category].map(isOutdated) ?? true {
                await load(category)
            }
            // The new cards are laid out hidden first, then play their entrance.
            try? await Task.sleep(for: .milliseconds(40))
            revealedCategory = category
        }
        .task {
            // Checked every minute rather than timed exactly, so the window also catches up after the Mac sleeps.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if loadingCategory == nil, results[category].map(isOutdated) == true {
                    await load(category)
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let current = results[category] {
            let words = NewsSettings.lines(mutedWords)
            let stories = current.cards(in: storyOrder)
                .filter { !$0.item.mentions(anyOf: words) }
            if current.items.isEmpty {
                ContentUnavailableView {
                    Label("No headlines right now", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your network connection, then press Refresh.")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if stories.isEmpty {
                ContentUnavailableView {
                    Label("Every story here is muted", systemImage: "eye.slash")
                } description: {
                    Text("Each of these headlines mentions one of your muted words.")
                } actions: {
                    SettingsLink {
                        Text("Edit Muted Words…")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                magazine(stories)
                    .id(category)
            }
        } else {
            MagazineSkeleton(columns: columns)
        }
    }

    /// The first story with a photo leads; everything else follows in the grid, in order.
    /// Each story keeps its index in the downloaded list, so ranks count muted stories too.
    private func magazine(_ stories: [Card]) -> some View {
        let hero = stories.first { $0.item.artwork == .photo } ?? stories[0]
        let cards = stories.filter { $0.id != hero.id }
        let isShown = revealedCategory == category
        let reservesSummary = stories.contains { $0.item.summary != nil }
        let reservesDetail = stories.contains { $0.item.detail != nil }
        return VStack(alignment: .leading, spacing: 26) {
            HeroCard(item: hero.item, showsSource: category.mixesSources, rank: rank(hero.index))
                .modifier(Reveal(index: 0, isShown: isShown))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { position, card in
                    StoryCard(item: card.item, showsSource: category.mixesSources, rank: rank(card.index),
                              reservesSummary: reservesSummary, reservesDetail: reservesDetail)
                        .modifier(Reveal(index: position + 1, isShown: isShown))
                        .scrollTransition(.animated(.smooth)) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.55)
                                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
                }
            }
        }
    }

    private func rank(_ index: Int) -> Int? {
        category.showsRanks ? index + 1 : nil
    }

    // MARK: Chrome

    private var refreshButton: some View {
        Button {
            Task { await refresh() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .spinning(loadingCategory != nil)
        }
        .keyboardShortcut("r")
        .disabled(loadingCategory != nil)
    }

    @ViewBuilder
    private var statusBar: some View {
        if let current = results[category] {
            HStack(spacing: 8) {
                Circle()
                    .fill(current.failedSourceIDs.isEmpty ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text("Updated \(current.fetchedAt.formatted(date: .omitted, time: .shortened))")
                if !current.failedSourceIDs.isEmpty {
                    let names = current.failedSourceIDs.map { SourceStyle.name(for: $0) }
                    Text("Couldn't reach \(names.formatted(.list(type: .and)))")
                }
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: Loading

    private func load(_ category: NewsCategory) async {
        loadingCategory = category
        let result = await service.fetch(category)
        // Switching categories cancels this task; keep what we had instead of storing errors.
        guard !Task.isCancelled else {
            if loadingCategory == category {
                loadingCategory = nil
            }
            return
        }
        withAnimation(.smooth) {
            results[category] = LoadedNews(items: result.items, topStoryIDs: result.topStoryIDs,
                                           failedSourceIDs: result.failedSourceIDs, fetchedAt: Date())
        }
        loadingCategory = nil
    }

    private func refresh() async {
        await load(category)
        WidgetReloader.refreshNow()
    }

    /// True once headlines are older than the refresh interval.
    private func isOutdated(_ news: LoadedNews) -> Bool {
        Date.now.timeIntervalSince(news.fetchedAt) >= refreshInterval.seconds
    }
}

/// Today's date over the paper's name, like the top of a front page.
private struct Masthead: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.5)
                .foregroundStyle(.secondary)
            Text("Tech Headlines")
                .font(.system(size: 36, weight: .black, design: .serif))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct LoadedNews {
    let items: [NewsItem]
    let topStoryIDs: [String]
    let failedSourceIDs: [String]
    let fetchedAt: Date

    /// The stories as cards in `order`. Each card keeps its index in the downloaded list.
    func cards(in order: StoryOrder) -> [Card] {
        let indices = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.arrange(items, topStoryIDs: topStoryIDs).map { Card(index: indices[$0.id] ?? 0, item: $0) }
    }
}

private struct Card: Identifiable {
    let index: Int
    let item: NewsItem

    var id: String { item.id }
}

extension View {
    /// Spins the refresh arrow while loading (macOS 15 and later; earlier versions pulse it).
    @ViewBuilder
    func spinning(_ isActive: Bool) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.rotate, isActive: isActive)
        } else {
            symbolEffect(.pulse, isActive: isActive)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 780)
}
