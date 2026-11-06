import AppKit
import ImageIO
import SwiftUI

/// Decodes and caches small previews so scrolling the Library never decodes
/// full-size screenshots on the main thread.
enum LibraryThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func cachedThumbnail(for image: ClipboardImage, maxPixel: Int) -> NSImage? {
        cache.object(forKey: key(for: image, maxPixel: maxPixel))
    }

    static func store(_ thumbnail: NSImage, for image: ClipboardImage, maxPixel: Int) {
        cache.setObject(thumbnail, forKey: key(for: image, maxPixel: maxPixel))
    }

    private static func key(for image: ClipboardImage, maxPixel: Int) -> NSString {
        "\(image.fingerprint)-\(maxPixel)" as NSString
    }

    /// Downscaled copy of `data`, safe to call off the main thread.
    nonisolated static func makeThumbnail(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Image preview that loads its thumbnail asynchronously.
struct LibraryThumbnailView: View {
    let image: ClipboardImage
    let maxPixel: Int
    var contentMode: ContentMode = .fill

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: image.fingerprint) {
            if let cached = LibraryThumbnailCache.cachedThumbnail(for: image, maxPixel: maxPixel) {
                thumbnail = cached
                return
            }

            let data = image.data
            let size = maxPixel
            let cgImage = await Task.detached(priority: .utility) {
                LibraryThumbnailCache.makeThumbnail(from: data, maxPixel: size)
            }.value

            guard let cgImage else { return }
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            LibraryThumbnailCache.store(nsImage, for: image, maxPixel: maxPixel)
            thumbnail = nsImage
        }
        .accessibilityHidden(true)
    }
}
