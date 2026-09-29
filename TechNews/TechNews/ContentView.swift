import NewsKit
import SwiftUI
import WidgetKit

/// Main window: headlines for the selected category, and a refresh button that also
/// asks the widgets to reload.
struct ContentView: View {
    @State private var category: NewsCategory = .all
    @State private var results: [NewsCategory: LoadedNews] = [:]
    @State private var loadingCategory: NewsCategory?

    private let service = NewsService()

    var body: some View {
        List(current?.items ?? []) { item in
            HeadlineRow(item: item, showsSource: category.mixesSources)
        }
        .overlay { overlay }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Category", selection: $category) {
                    ForEach(NewsCategory.allCases, id: \.self) { category in
                        Text(category.localizedTitle).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(loadingCategory != nil)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .task(id: category) {
            if results[category] == nil {
                await load(category)
            }
        }
    }

    private var current: LoadedNews? {
        results[category]
    }

    @ViewBuilder
    private var overlay: some View {
        if current == nil {
            ProgressView()
        } else if current?.items.isEmpty == true {
            ContentUnavailableView {
                Label("No headlines right now", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your network connection, then press Refresh.")
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if let current {
            HStack(spacing: 12) {
                Text("Updated \(current.fetchedAt.formatted(date: .omitted, time: .shortened))")
                if !current.failedSourceIDs.isEmpty {
                    let names = current.failedSourceIDs.map { SourceStyle.name(for: $0) }
                    Text("Couldn't reach \(names.formatted(.list(type: .and)))")
                }
                Spacer()
                if loadingCategory == category {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

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
        results[category] = LoadedNews(items: result.items, failedSourceIDs: result.failedSourceIDs, fetchedAt: Date())
        loadingCategory = nil
    }

    private func refresh() async {
        await load(category)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct LoadedNews {
    let items: [NewsItem]
    let failedSourceIDs: [String]
    let fetchedAt: Date
}

#Preview {
    ContentView()
}
