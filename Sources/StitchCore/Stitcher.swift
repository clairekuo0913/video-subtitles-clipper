import CoreGraphics
import Foundation
import ImageIO

public enum Stitcher {
    /// 不透明黑底畫布。
    static func makeCanvas(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    /// 垂直拼接。寬度以第一項為基準；異寬者等比縮放（高度四捨五入，至少 1）。
    /// 所有項目（含幕間）無縫，黑底；純字幕以 `band` 裁切；接著繪製標記（座標以長圖寬度正規化），最後套用輸出倍率。
    /// 空清單回傳 nil；無標記時與舊行為逐像素相同。
    public static func stitch(_ list: ComposeList, band: CropBand,
                              outputScale: OutputScale = .default,
                              annotations: [Annotation] = []) -> CGImage? {
        guard let first = list.scenes.first?.first else { return nil }
        let width = first.image.width

        struct Piece { let image: CGImage; let height: Int }
        var pieces: [Piece] = []
        for item in list.scenes.joined() {
            let source: CGImage
            if item.kind == .subtitle {
                guard let cropped = SubtitleCrop.crop(item.image, band: band) else { return nil }
                source = cropped
            } else {
                source = item.image
            }
            let h = source.width == width
                ? source.height
                : max(1, Int((Double(source.height) * Double(width) / Double(source.width))
                    .rounded(.toNearestOrAwayFromZero)))
            pieces.append(Piece(image: source, height: h))
        }
        let totalHeight = pieces.reduce(0) { $0 + $1.height }

        guard let ctx = makeCanvas(width: width, height: totalHeight) else { return nil }
        ctx.interpolationQuality = .high

        var top = 0
        for piece in pieces {
            // CGContext 原點在左下
            let rect = CGRect(x: 0, y: totalHeight - top - piece.height, width: width, height: piece.height)
            ctx.draw(piece.image, in: rect)
            top += piece.height
        }
        guard var stitched = ctx.makeImage() else { return nil }
        if !annotations.isEmpty {
            guard let marked = AnnotationRenderer.render(onto: stitched, annotations: annotations) else { return nil }
            stitched = marked
        }
        return outputScale.apply(to: stitched)
    }
}

public enum PNGOutput {
    public static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// `subtitles-yyyyMMdd-HHmmss.png`
    public static func filename(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "subtitles-\(f.string(from: date)).png"
    }
}
