import NewsKit
import SwiftUI

/// First version of the main window: fetches every source once and lists the headlines.
/// It exists to prove the sandboxed app can reach the network through NewsKit;
/// the full browser (categories, refresh button) comes next.
struct ContentView: View {
    @State private var items: [NewsItem] = []
    @State private var isLoading = true

    var body: some View {
        List(items) { item in
            Link(item.title, destination: item.url)
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task {
            items = await NewsService().fetch(.all).items
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
