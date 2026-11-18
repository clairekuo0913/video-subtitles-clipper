import CoreGraphics
import Foundation
import ImageIO

public struct LoadedImage {
    public let name: String
    public let image: CGImage
    public let thumbnail: CGImage

    public init(name: String, image: CGImage, thumbnail: CGImage) {
        self.name = name; self.image = image; self.thumbnail = thumbnail
    }
}

public enum ImageLoading {
    public static let thumbnailMaxPixel = 3000

    /// 讀取單一圖片檔；非圖片或無法解碼回傳 nil。原圖延遲解碼，縮圖以 ImageIO 降採樣。
    public static func load(url: URL) -> LoadedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) != nil,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumb = thumbnail(source: source)
        else { return nil }
        return LoadedImage(name: url.lastPathComponent, image: image, thumbnail: thumb)
    }

    /// 多檔依檔名自然排序後載入，忽略非圖片。
    public static func load(urls: [URL]) -> [LoadedImage] {
        naturalSorted(urls, by: { $0.lastPathComponent }).compactMap { load(url: $0) }
    }

    /// 由已有的 CGImage（如剪貼簿）產生縮圖。
    public static func thumbnail(of image: CGImage) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest),
              let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return thumbnail(source: source)
    }

    private static func thumbnail(source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
