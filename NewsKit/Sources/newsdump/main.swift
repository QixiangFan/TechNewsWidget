import Foundation
import NewsKit

// Usage:
//   swift run newsdump                          Summary of every source, the top stories and the cache size per category.
//   swift run newsdump <source>                 Every item from one source, e.g. `swift run newsdump hn`.
//   swift run newsdump <source> --thumbnails    Also downloads and shrinks each item's image, printing the sizes.

let service = NewsService()
let arguments = CommandLine.arguments.dropFirst()

if let sourceID = arguments.first {
    guard let source = NewsSource.named(sourceID) else {
        print("Unknown source '\(sourceID)'. Available: \(NewsSource.all.map(\.id).joined(separator: ", "))")
        exit(1)
    }
    let items: [NewsItem]
    do {
        items = try await service.fetchItems(from: source)
    } catch {
        print("Failed: \(error.localizedDescription)")
        exit(1)
    }
    for (index, item) in items.enumerated() {
        print("\(index + 1). \(item.title)")
        if let detail = item.detail { print("   \(detail)") }
        if let summary = item.summary { print("   ≡ \(summary)") }
        print("   \(item.url.absoluteString)  \(item.date.map { "\($0)" } ?? "no date")")
        if let imageURL = item.imageURL { print("   🖼 \(imageURL.absoluteString)") }
    }

    if arguments.contains("--thumbnails") {
        // A throwaway folder, so the widget's own cache is never touched.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("newsdump-thumbnails-\(UUID().uuidString)", isDirectory: true)
        let store = ThumbnailStore(directory: directory)
        print("\nThumbnails (downloaded → saved):")
        var downloaded = 0, saved = 0, failed = 0
        for (index, item) in items.enumerated() {
            guard let imageURL = item.imageURL else { continue }
            if let result = await store.download(imageURL) {
                downloaded += result.downloadedBytes
                saved += result.thumbnail.count
                print(String(format: "%3d. %8.1f KB → %5.1f KB  ", index + 1,
                             Double(result.downloadedBytes) / 1024, Double(result.thumbnail.count) / 1024)
                      + result.url.absoluteString)
            } else {
                failed += 1
                print(String(format: "%3d. failed                    ", index + 1) + imageURL.absoluteString)
            }
        }
        print(String(format: "Total %.1f KB downloaded, %.1f KB saved, %d failed", Double(downloaded) / 1024,
                     Double(saved) / 1024, failed))
        try? FileManager.default.removeItem(at: directory)
    }
    exit(0)
}

// Fetch every source concurrently, then print them in declaration order.
var results: [String: (Result<[NewsItem], Error>, TimeInterval)] = [:]
await withTaskGroup(of: (String, Result<[NewsItem], Error>, TimeInterval).self) { group in
    for source in NewsSource.all {
        group.addTask {
            let start = Date()
            do {
                let items = try await service.fetchItems(from: source)
                return (source.id, .success(items), Date().timeIntervalSince(start))
            } catch {
                return (source.id, .failure(error), Date().timeIntervalSince(start))
            }
        }
    }
    for await (id, result, elapsed) in group {
        results[id] = (result, elapsed)
    }
}

var itemsBySource: [String: [NewsItem]] = [:]
for source in NewsSource.all {
    guard let (result, elapsed) = results[source.id] else { continue }
    let timing = String(format: "%.1fs", elapsed)
    switch result {
    case let .success(items):
        itemsBySource[source.id] = items
        let dated = items.filter { $0.date != nil }.count
        let summarized = items.filter { $0.summary != nil }.count
        let illustrated = items.filter { $0.imageURL != nil }.count
        print("✅ \(source.name) [\(source.id)] \(items.count) items: \(dated) dated, \(summarized) with summary, "
              + "\(illustrated) with image, \(timing)")
        for item in items.prefix(3) {
            print("   · \(item.title)")
            if let summary = item.summary { print("     ≡ \(summary)") }
        }
    case let .failure(error):
        print("❌ \(source.name) [\(source.id)] \(timing): \(error.localizedDescription)")
    }
}

// The stories each category moves to the front, with the other outlets that reported them.
for category in NewsCategory.allCases {
    let lists = NewsSource.sources(for: category).compactMap { itemsBySource[$0.id] }
    let topStories = TopStories.pick(from: lists, now: Date())
    guard !topStories.isEmpty else { continue }
    let coverage = TopStories.coverage(in: lists)
    print("\nTop stories in \(category.rawValue):")
    for (index, item) in topStories.enumerated() {
        print("   \(index + 1). [\(item.sourceID)] \(item.title)")
        print("      also in: \((coverage[item.id] ?? []).sorted().joined(separator: ", "))")
    }
}

print("\nCache size per category (limit \(CacheLimits.maxFileBytes / 1024) KB each):")
var total = 0
for category in NewsCategory.allCases {
    let lists = NewsSource.sources(for: category).compactMap { itemsBySource[$0.id] }
    let topStories = TopStories.pick(from: lists, now: Date())
    let items = NewsService.interleave(lists, limit: CacheLimits.maxItemsPerCategory, keeping: topStories)
    let bytes = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items,
                                                topStoryIDs: topStories.map(\.id))).count
    total += bytes
    let name = category.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
    print(String(format: "   \(name) %3d items  %6.1f KB", items.count, Double(bytes) / 1024))
}
print(String(format: "   total                    %6.1f KB", Double(total) / 1024))
