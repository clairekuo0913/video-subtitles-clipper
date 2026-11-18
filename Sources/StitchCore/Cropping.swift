import CoreGraphics

/// 字幕列範圍：圖片高度比例（0–1，由上往下），全寬。不變量：0 ≤ top、top + minHeight ≤ bottom ≤ 1。
public struct CropBand: Equatable {
    public static let minHeight = 0.02
    public static let `default` = CropBand(top: 0.85, bottom: 1.0)

    public let top: Double
    public let bottom: Double

    /// 夾限建構：維持 0–1 與最小高度。
    public init(top: Double, bottom: Double) {
        let t = min(max(top, 0), 1 - Self.minHeight)
        self.top = t
        self.bottom = min(max(bottom, t + Self.minHeight), 1)
    }

    /// 移動上緣（下緣不動），夾在 0 與 bottom - minHeight 之間。
    public func movingTop(to value: Double) -> CropBand {
        CropBand(top: min(max(value, 0), bottom - Self.minHeight), bottom: bottom)
    }

    /// 移動下緣（上緣不動），夾在 top + minHeight 與 1 之間。
    public func movingBottom(to value: Double) -> CropBand {
        CropBand(top: top, bottom: min(max(value, top + Self.minHeight), 1))
    }

    /// 像素列範圍（由上往下）：以四捨五入（.5 進位）計算，至少 1 列、不越界。
    public func rows(imageHeight: Int) -> Range<Int> {
        let h = Double(imageHeight)
        let start = min(max(Int((top * h).rounded(.toNearestOrAwayFromZero)), 0), max(imageHeight - 1, 0))
        let end = min(max(Int((bottom * h).rounded(.toNearestOrAwayFromZero)), start + 1), imageHeight)
        return start..<end
    }
}

public enum SubtitleCrop {
    /// 取 band 範圍的全寬區域。
    public static func crop(_ image: CGImage, band: CropBand) -> CGImage? {
        let r = band.rows(imageHeight: image.height)
        return image.cropping(to: CGRect(x: 0, y: r.lowerBound, width: image.width, height: r.count))
    }
}

/// 紅框座標換算（不依賴 UI）。`displayHeight` 為縮放 1.0 時圖片顯示框高度（point），
/// `zoom` 為目前檢視縮放係數；y 為圖片顯示框內（已縮放）由上往下的位置。
public enum CropBandGeometry {
    public static func ratio(forY y: Double, displayHeight: Double, zoom: Double) -> Double {
        let h = displayHeight * zoom
        guard h > 0 else { return 0 }
        return min(max(y / h, 0), 1)
    }

    public static func y(forRatio ratio: Double, displayHeight: Double, zoom: Double) -> Double {
        min(max(ratio, 0), 1) * displayHeight * zoom
    }
}
