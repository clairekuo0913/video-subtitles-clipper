import CoreGraphics

/// 輸出解析度倍率。
public enum OutputScale: Int, CaseIterable {
    case percent25 = 25, percent50 = 50, percent75 = 75, percent100 = 100

    public static let `default` = OutputScale.percent100
    public var percent: Int { rawValue }
    public var factor: Double { Double(rawValue) / 100 }

    /// round(尺寸 × 倍率)，至少 1 px。
    public func size(width: Int, height: Int) -> (width: Int, height: Int) {
        func scaled(_ v: Int) -> Int { max(1, Int((Double(v) * factor).rounded(.toNearestOrAwayFromZero))) }
        return (scaled(width), scaled(height))
    }

    /// 100% 原樣回傳（不重繪）；其餘以高品質插值縮放。
    public func apply(to image: CGImage) -> CGImage {
        if self == .percent100 { return image }
        let s = size(width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: s.width, height: s.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: s.width, height: s.height))
        return ctx.makeImage() ?? image
    }
}
