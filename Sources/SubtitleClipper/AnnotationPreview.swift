import CoreGraphics
import Foundation
import StitchCore

/// 標記覆蓋層的預覽管線：以縮圖組一張降採樣的「預覽長圖」（不含標記）當底圖並快取，
/// 再用 `AnnotationRenderer.overlay` 畫出透明覆蓋層。請求會合併（同時只跑一個，結束後取最新請求）。
@MainActor
final class AnnotationPreview: ObservableObject {
    struct BaseKey: Equatable {
        let ids: [UUID]
        let kinds: [ItemKind]
        let band: CropBand
    }

    struct Request {
        let key: BaseKey
        let thumbs: [CGImage]
        let ratio: CGFloat
        let annotations: [Annotation]
    }

    @Published private(set) var overlay: CGImage?

    private var cached: (key: BaseKey, image: CGImage)?
    private var wanted: Request?
    private var running = false

    func request(_ r: Request) {
        wanted = r
        guard !running else { return }
        running = true
        Task { [weak self] in
            while let self, let next = self.wanted {
                self.wanted = nil
                let cache = self.cached
                let out = await Task.detached(priority: .userInitiated) { Self.compute(next, cached: cache) }.value
                self.cached = out.base
                self.overlay = out.overlay
            }
            self?.running = false
        }
    }

    /// 預覽底圖寬度上限與總像素上限（控制大長圖記憶體）。
    nonisolated private static let maxWidth = 800.0
    nonisolated private static let maxPixels = 16_000_000.0

    nonisolated private static func compute(_ r: Request, cached: (key: BaseKey, image: CGImage)?)
        -> (base: (key: BaseKey, image: CGImage)?, overlay: CGImage?) {
        guard !r.annotations.isEmpty else { return (nil, nil) }
        let base: CGImage
        if let c = cached, c.key == r.key {
            base = c.image
        } else {
            guard let b = buildBase(r) else { return (nil, nil) }
            base = b
        }
        return ((r.key, base), AnnotationRenderer.overlay(for: base, annotations: r.annotations))
    }

    nonisolated private static func buildBase(_ r: Request) -> CGImage? {
        guard let first = r.thumbs.first, first.width > 0 else { return nil }
        let w = Double(first.width)
        let factor = min(1, maxWidth / w, (maxPixels / max(Double(r.ratio), 0.001)).squareRoot() / w)
        var list = ComposeList()
        for (i, img) in r.thumbs.enumerated() {
            let item = list.append(image: downscale(img, by: factor), name: "")
            if item.kind != r.key.kinds[i] { _ = list.setKind(id: item.id, to: r.key.kinds[i]) }
        }
        return Stitcher.stitch(list, band: r.key.band)
    }

    nonisolated private static func downscale(_ image: CGImage, by f: Double) -> CGImage {
        guard f < 0.999 else { return image }
        let w = max(1, Int((Double(image.width) * f).rounded())), h = max(1, Int((Double(image.height) * f).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
