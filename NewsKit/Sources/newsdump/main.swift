import Foundation
import NewsKit

// Usage:
//   swift run newsdump            Summary of every source plus the cache size per category.
//   swift run newsdump <source>   Every item from one source, e.g. `swift run newsdump hn`.

let service = NewsService()
let arguments = CommandLine.arguments.dropFirst()

if let sourceID = arguments.first {
    guard let source = NewsSource.named(sourceID) else {
        print("Unknown source '\(sourceID)'. Available: \(NewsSource.all.map(\.id).joined(separator: ", "))")
        exit(1)
    }
    do {
        for (index, item) in try await service.fetchItems(from: source).enumerated() {
            print("\(index + 1). \(item.title)")
            if let detail = item.detail { print("   \(detail)") }
            print("   \(item.url.absoluteString)  \(item.date.map { "\($0)" } ?? "no date")")
        }
    } catch {
        print("Failed: \(error.localizedDescription)")
        exit(1)
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
        print("✅ \(source.name) [\(source.id)] \(items.count) items, \(dated) dated, \(timing)")
        for item in items.prefix(3) {
            print("   · \(item.title)")
        }
    case let .failure(error):
        print("❌ \(source.name) [\(source.id)] \(timing): \(error.localizedDescription)")
    }
}

print("\nCache size per category (limit \(CacheLimits.maxFileBytes / 1024) KB each):")
var total = 0
for category in NewsCategory.allCases {
    let lists = NewsSource.sources(for: category).compactMap { itemsBySource[$0.id] }
    let items = NewsService.interleave(lists, limit: CacheLimits.maxItemsPerCategory)
    let bytes = try NewsCache.encode(CachedNews(fetchedAt: Date(), items: items)).count
    total += bytes
    let name = category.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
    print(String(format: "   \(name) %3d items  %6.1f KB", items.count, Double(bytes) / 1024))
}
print(String(format: "   total                    %6.1f KB", Double(total) / 1024))
