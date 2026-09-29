import CryptoKit
import Foundation
import ImageIO

/// What `ThumbnailStore.download(_:)` fetched; `newsdump --thumbnails` prints it.
public struct ThumbnailDownload: Sendable {
    /// The address that worked: the resized one from `ThumbnailStore.downloadURL(for:)`, or the original.
    public let url: URL
    /// Size of the downloaded image before shrinking.
    public let downloadedBytes: Int
    /// The JPEG thumbnail that was saved.
    public let thumbnail: Data
}

/// Small JPEG thumbnails of article images, kept in `<Caches>/TechNews/thumbs`.
///
/// A widget cannot load images while it is on screen, so the timeline provider downloads them
/// up front. Each image is shrunk to at most `CacheLimits.thumbnailMaxPixelSize` pixels, and the
/// folder is capped at `CacheLimits.maxThumbnailBytes` by deleting the oldest files first.
public struct ThumbnailStore: Sendable {
    private let directory: URL
    private let session: URLSession

    public init(directory: URL? = nil, session: URLSession = .newsKit) {
        self.directory = directory ?? NewsCache.defaultDirectory.appendingPathComponent("thumbs", isDirectory: true)
        self.session = session
    }

    /// Thumbnails for `items`, keyed by `NewsItem.id`, downloading the missing ones concurrently.
    /// Whatever is not ready within `timeout` seconds is left out; those rows show no image.
    public func thumbnails(for items: [NewsItem], timeout: TimeInterval = 5) async -> [String: Data] {
        var result = cachedThumbnails(for: items)
        // Several items can share one image, e.g. a site's default picture.
        var itemsByImage: [URL: [NewsItem]] = [:]
        for item in items where result[item.id] == nil {
            if let imageURL = item.imageURL {
                itemsByImage[imageURL, default: []].append(item)
            }
        }
        guard !itemsByImage.isEmpty else { return result }

        await withTaskGroup(of: (URL, Data?)?.self) { group in
            for imageURL in itemsByImage.keys {
                group.addTask { (imageURL, await download(imageURL)?.thumbnail) }
            }
            // The deadline task returns nil, which stops waiting for downloads still running.
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            var remaining = itemsByImage.count
            for await finished in group {
                guard case let (imageURL, thumbnail)? = finished else { break }
                if let thumbnail {
                    for item in itemsByImage[imageURL] ?? [] {
                        result[item.id] = thumbnail
                    }
                }
                remaining -= 1
                if remaining == 0 { break }
            }
            group.cancelAll()
        }
        return result
    }

    /// Thumbnails already on disk, keyed by `NewsItem.id`. Never uses the network.
    public func cachedThumbnails(for items: [NewsItem]) -> [String: Data] {
        var result: [String: Data] = [:]
        for item in items {
            if let imageURL = item.imageURL, let data = try? Data(contentsOf: fileURL(for: imageURL)) {
                result[item.id] = data
            }
        }
        return result
    }

    /// Downloads one image (the resized address first, then the original), shrinks it and saves the thumbnail.
    public func download(_ imageURL: URL) async -> ThumbnailDownload? {
        for candidate in Self.candidateURLs(for: imageURL) {
            guard !Task.isCancelled else { return nil }
            do {
                let (data, response) = try await session.data(from: candidate)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continue
                }
                guard let thumbnail = Self.downsample(data, maxPixelSize: CacheLimits.thumbnailMaxPixelSize) else {
                    continue
                }
                save(thumbnail, for: imageURL)
                return ThumbnailDownload(url: candidate, downloadedBytes: data.count, thumbnail: thumbnail)
            } catch {
                NewsService.logger.debug("Thumbnail \(candidate.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    /// Deletes thumbnails older than `CacheLimits.maxAge`. Returns how many were removed.
    @discardableResult
    public func removeExpired(now: Date = Date()) -> Int {
        var removed = 0
        for file in files() where now.timeIntervalSince(file.created) >= CacheLimits.maxAge {
            if (try? FileManager.default.removeItem(at: file.url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    // MARK: Addresses

    /// The address to download: https, and resized by the image host where it supports that,
    /// so a multi-megabyte original arrives as a picture of 10–20 KB.
    public static func downloadURL(for imageURL: URL) -> URL {
        guard var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false) else {
            return imageURL
        }
        if components.scheme == "http" {
            components.scheme = "https"
        }
        let width = CacheLimits.thumbnailMaxPixelSize
        switch components.host {
        case "img.ithome.com":
            // Baidu Cloud image processing.
            components.setQueryItem("x-bce-process", "image/resize,w_\(width)/format,f_jpg/quality,q_70")
        case "s3.ifanr.com":
            // Qiniu: the whole query is the processing command.
            components.query = "imageMogr2/thumbnail/\(width)x/format/jpg/quality/70"
        case "imgslim.geekpark.net":
            components.query = "imageView2/2/w/\(width)/format/jpg/q/70"
        case "platform.theverge.com", "techcrunch.com":
            // WordPress image CDN.
            components.setQueryItem("w", "\(width)")
        case "cdn.arstechnica.net":
            // WordPress keeps pre-sized copies next to the original; 384x216 is the smallest.
            components.path = components.path.replacingOccurrences(
                of: #"-\d+x\d+(\.\w+)$"#, with: "-384x216$1", options: .regularExpression)
        default:
            break
        }
        return components.url ?? imageURL
    }

    /// The resized address, then the original over https in case the host rejects the resize.
    static func candidateURLs(for imageURL: URL) -> [URL] {
        let resized = downloadURL(for: imageURL)
        var original = URLComponents(url: imageURL, resolvingAgainstBaseURL: false)
        if original?.scheme == "http" {
            original?.scheme = "https"
        }
        let fallback = original?.url ?? imageURL
        return resized == fallback ? [resized] : [resized, fallback]
    }

    // MARK: Shrinking

    /// Shrinks an image so its longer side is at most `maxPixelSize` pixels and encodes it as JPEG.
    /// Transparent areas become white, since JPEG has no transparency. A JPEG that is already small
    /// enough (most image hosts resize for us) is returned unchanged, because encoding it again
    /// would only make it bigger. Nil if `data` is not an image.
    static func downsample(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if CGImageSourceGetType(source) as String? == "public.jpeg",
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxPixelSize,
           properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1 {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)?.flattenedOntoWhite() else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        // 0.6 looks the same as higher settings at thumbnail size and is about 20% smaller than 0.7.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // MARK: Files

    private func fileURL(for imageURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(imageURL.absoluteString.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).jpg")
    }

    /// Writes a thumbnail, then deletes the oldest ones until the folder fits `CacheLimits.maxThumbnailBytes`.
    func save(_ thumbnail: Data, for imageURL: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? thumbnail.write(to: fileURL(for: imageURL), options: .atomic)

        let oldestFirst = files().sorted { $0.created < $1.created }
        var total = oldestFirst.reduce(0) { $0 + $1.size }
        for file in oldestFirst where total > CacheLimits.maxThumbnailBytes {
            if (try? FileManager.default.removeItem(at: file.url)) != nil {
                total -= file.size
            }
        }
    }

    private func files() -> [(url: URL, size: Int, created: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.filter { $0.pathExtension == "jpg" }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.creationDate ?? .distantPast)
        }
    }
}

private extension URLComponents {
    /// Sets the query parameter `name`, replacing any existing value and keeping the other parameters.
    mutating func setQueryItem(_ name: String, _ value: String) {
        var items = (queryItems ?? []).filter { $0.name != name }
        items.append(URLQueryItem(name: name, value: value))
        queryItems = items
    }
}

private extension CGImage {
    /// The image drawn over white, or the image itself when it has no alpha channel.
    func flattenedOntoWhite() -> CGImage? {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return self
        default:
            break
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(self, in: rect)
        return context.makeImage()
    }
}
