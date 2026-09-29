import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NewsKit

/// Encodes a solid (or fully transparent) test image as `type`, e.g. "public.png".
private func imageData(width: Int, height: Int, type: String, transparent: Bool = false) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: (transparent ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    if !transparent {
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func properties(of data: Data) -> (type: String?, width: Int, height: Int) {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    return (CGImageSourceGetType(source) as String?, values[kCGImagePropertyPixelWidth] as! Int,
            values[kCGImagePropertyPixelHeight] as! Int)
}

private func temporaryStore() -> ThumbnailStore {
    ThumbnailStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true))
}

private func item(_ name: String) -> NewsItem {
    NewsItem(title: name, url: URL(string: "https://example.com/\(name)")!, sourceID: "s",
             imageURL: URL(string: "https://img.example.com/\(name).jpg")!)
}

@Suite struct ThumbnailAddressTests {
    private func resized(_ string: String) -> String {
        ThumbnailStore.downloadURL(for: URL(string: string)!).absoluteString
    }

    @Test func asksEachImageHostForASmallCopy() {
        #expect(resized("https://img.ithome.com/newsuploadfiles/2026/9/a.png?x-bce-process=image/format,f_auto")
            == "https://img.ithome.com/newsuploadfiles/2026/9/a.png?x-bce-process=image/resize,w_320/format,f_jpg/quality,q_70")
        #expect(resized("https://s3.ifanr.com/wp-content/uploads/2026/09/a.png")
            == "https://s3.ifanr.com/wp-content/uploads/2026/09/a.png?imageMogr2/thumbnail/320x/format/jpg/quality/70")
        #expect(resized("https://imgslim.geekpark.net/uploads/image/file/44/52/a.png")
            == "https://imgslim.geekpark.net/uploads/image/file/44/52/a.png?imageView2/2/w/320/format/jpg/q/70")
        #expect(resized("https://platform.theverge.com/a.webp?quality=90&strip=all&crop=0,0,100,100")
            == "https://platform.theverge.com/a.webp?quality=90&strip=all&crop=0,0,100,100&w=320")
        #expect(resized("https://techcrunch.com/wp-content/uploads/2026/09/OpenAI.jpg?w=1024")
            == "https://techcrunch.com/wp-content/uploads/2026/09/OpenAI.jpg?w=320")
        #expect(resized("https://cdn.arstechnica.net/wp-content/uploads/2026/09/Getty-1-1152x648.jpg")
            == "https://cdn.arstechnica.net/wp-content/uploads/2026/09/Getty-1-384x216.jpg")
    }

    @Test func leavesOtherHostsAloneButUpgradesToHTTPS() {
        #expect(resized("https://cdn.arstechnica.net/wp-content/uploads/2026/09/header-1152x648-1790642597.jpg")
            == "https://cdn.arstechnica.net/wp-content/uploads/2026/09/header-1152x648-1790642597.jpg")
        #expect(resized("https://github.com/apple.png?size=160") == "https://github.com/apple.png?size=160")
        #expect(resized("http://example.com/a.jpg") == "https://example.com/a.jpg")
    }

    @Test func triesTheOriginalWhenTheResizedCopyFails() {
        let original = URL(string: "http://s3.ifanr.com/a.png")!
        #expect(ThumbnailStore.candidateURLs(for: original).map(\.absoluteString) == [
            "https://s3.ifanr.com/a.png?imageMogr2/thumbnail/320x/format/jpg/quality/70",
            "https://s3.ifanr.com/a.png",
        ])
        #expect(ThumbnailStore.candidateURLs(for: URL(string: "https://example.com/a.jpg")!).count == 1)
    }
}

@Suite struct DownsampleTests {
    @Test func shrinksLargeImagesToJPEG() throws {
        let thumbnail = try #require(ThumbnailStore.downsample(imageData(width: 1000, height: 500, type: "public.png"),
                                                               maxPixelSize: 320))
        let result = properties(of: thumbnail)
        #expect(result.type == "public.jpeg")
        #expect(result.width == 320)
        #expect(result.height == 160)
    }

    @Test func keepsSmallJPEGsByteForByte() {
        let small = imageData(width: 320, height: 180, type: "public.jpeg")
        #expect(ThumbnailStore.downsample(small, maxPixelSize: 320) == small)
    }

    @Test func turnsTransparencyWhite() throws {
        let thumbnail = try #require(ThumbnailStore.downsample(
            imageData(width: 400, height: 400, type: "public.png", transparent: true), maxPixelSize: 320))
        let image = try #require(CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithData(thumbnail as CFData, nil)!, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(ThumbnailStore.downsample(Data("<html>blocked</html>".utf8), maxPixelSize: 320) == nil)
    }
}

@Suite struct ThumbnailFileTests {
    @Test func servesSavedThumbnailsWithoutTheNetwork() async {
        let store = temporaryStore()
        let saved = item("saved")
        store.save(Data("jpeg".utf8), for: saved.imageURL!)
        let noImage = NewsItem(title: "text only", url: URL(string: "https://example.com/t")!, sourceID: "s")

        let thumbnails = await store.thumbnails(for: [saved, noImage])
        #expect(thumbnails == [saved.id: Data("jpeg".utf8)])
    }

    @Test func deletesTheOldestThumbnailsBeyondTheSizeCap() {
        let store = temporaryStore()
        let items = (0..<5).map { item("i\($0)") }
        for item in items {
            store.save(Data(count: 100 * 1024), for: item.imageURL!)
        }
        let kept = store.cachedThumbnails(for: items)
        #expect(kept.count * 100 * 1024 <= CacheLimits.maxThumbnailBytes)
        #expect(Set(kept.keys) == Set(items.suffix(kept.count).map(\.id)))
    }

    @Test func removesExpiredThumbnails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsKitTests-\(UUID().uuidString)", isDirectory: true)
        let store = ThumbnailStore(directory: directory)
        let old = item("old")
        store.save(Data("jpeg".utf8), for: old.imageURL!)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let now = Date()
        try FileManager.default.setAttributes([.creationDate: now.addingTimeInterval(-CacheLimits.maxAge - 60)],
                                              ofItemAtPath: file.path)

        #expect(store.removeExpired(now: now) == 1)
        #expect(store.cachedThumbnails(for: [old]).isEmpty)
    }
}
