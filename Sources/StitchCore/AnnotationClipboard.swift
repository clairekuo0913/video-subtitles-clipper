import CoreGraphics
import Foundation

/// 標記的內部剪貼簿（不依賴 AppKit、不碰系統剪貼簿）：保存複製的快照與貼上次數。
public struct AnnotationClipboard {
    /// 每次貼上累加的偏移（正規化寬度單位，x、y 皆加）。
    public static let offsetStep: CGFloat = 0.02

    private var snapshot: Annotation?
    private var pasteCount = 0

    public init() {}

    public var hasContent: Bool { snapshot != nil }

    /// 複製：覆蓋舊內容並將貼上次數歸零。
    public mutating func copy(_ annotation: Annotation) {
        snapshot = annotation
        pasteCount = 0
    }

    public mutating func clear() {
        snapshot = nil
        pasteCount = 0
    }

    /// 產生副本（新 id）：自原位置右下偏移 `offsetStep × 貼上次數`，並夾限在長圖範圍內。沒有內容回傳 nil。
    public mutating func pasted(canvasHeightRatio: CGFloat) -> Annotation? {
        guard let snapshot else { return nil }
        pasteCount += 1
        let d = Self.offsetStep * CGFloat(pasteCount)
        let moved = snapshot.moved(dx: d, dy: d, canvasHeightRatio: canvasHeightRatio)
        return Annotation(shape: moved.shape).clamped(canvasHeightRatio: canvasHeightRatio)
    }
}
