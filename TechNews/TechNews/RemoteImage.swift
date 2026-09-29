import AppKit
import NewsKit
import SwiftUI

/// Loads article pictures for the main window. Pictures are kept in memory only: the session is
/// `URLSession.newsKit` (ephemeral, no URLCache), so the app never writes images to disk.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The picture at `url`, downloading it once even when several views ask at the same time.
    func image(for url: URL) async -> NSImage? {
        if let image = cachedImage(for: url) { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await URLSession.newsKit.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

/// A remote picture, cropped to fill its frame. The placeholder shows until the picture arrives,
/// then the picture fades in over it; pictures already in memory appear without a flash.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cachedImage(for: $0) })
    }

    var body: some View {
        Color.clear
            .overlay { placeholder() }
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard image == nil, let url else { return }
                let loaded = await ImageLoader.shared.image(for: url)
                withAnimation(.easeOut(duration: 0.4)) {
                    image = loaded
                }
            }
    }
}
