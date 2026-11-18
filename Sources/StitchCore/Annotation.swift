import CoreGraphics
import Foundation

public enum AnnotationKind: Equatable {
    case text, rectangle, arrow, mosaic, image
}

/// 座標一律以長圖寬度正規化：x、y、寬、高皆除以長圖寬度（y 由上往下）。
/// 故長圖範圍為 x∈[0,1]、y∈[0,canvasHeightRatio]（canvasHeightRatio = 長圖高 / 寬）。
public enum AnnotationShape: Equatable {
    case text(rect: CGRect, text: String, style: TextStyle)
    case rectangle(rect: CGRect, style: LineStyle)
    case arrow(start: CGPoint, end: CGPoint, style: LineStyle)
    case mosaic(rect: CGRect)
    /// 貼上的圖片；長寬比鎖定（見 `AnnotationImagePlacement`）。圖片以參考相等比較，撤銷快照共用同一個 CGImage。
    case image(rect: CGRect, image: CGImage)

    public static func == (l: AnnotationShape, r: AnnotationShape) -> Bool {
        switch (l, r) {
        case let (.text(a, b, c), .text(d, e, f)): return a == d && b == e && c == f
        case let (.rectangle(a, b), .rectangle(c, d)): return a == c && b == d
        case let (.arrow(a, b, c), .arrow(d, e, f)): return a == d && b == e && c == f
        case let (.mosaic(a), .mosaic(b)): return a == b
        case let (.image(a, i), .image(b, j)): return a == b && i === j
        default: return false
        }
    }
}

public enum AnnotationLimits {
    /// 最小邊長（箭頭為最小長度），相對長圖寬度。
    public static let minSize: CGFloat = 0.02
}

public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public var shape: AnnotationShape

    public init(id: UUID = UUID(), shape: AnnotationShape) {
        self.id = id
        self.shape = shape
    }

    public var kind: AnnotationKind {
        switch shape {
        case .text: return .text
        case .rectangle: return .rectangle
        case .arrow: return .arrow
        case .mosaic: return .mosaic
        case .image: return .image
        }
    }

    /// 外框（正規化座標）。
    public var bounds: CGRect {
        switch shape {
        case let .text(r, _, _), let .rectangle(r, _), let .mosaic(r), let .image(r, _): return r
        case let .arrow(s, e, _):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
        }
    }

    // MARK: 夾限

    /// 夾限於長圖範圍並套用最小尺寸（箭頭含兩端點）。
    public func clamped(canvasHeightRatio h: CGFloat) -> Annotation {
        var copy = self
        switch shape {
        case let .text(r, t, s): copy.shape = .text(rect: Self.clamp(r, h), text: t, style: s)
        case let .rectangle(r, s): copy.shape = .rectangle(rect: Self.clamp(r, h), style: s)
        case let .mosaic(r): copy.shape = .mosaic(rect: Self.clamp(r, h))
        case let .image(r, img): copy.shape = .image(rect: Self.clampKeepingAspect(r, h), image: img)
        case let .arrow(a, b, s):
            let (a2, b2) = Self.clamp(start: a, end: b, h)
            copy.shape = .arrow(start: a2, end: b2, style: s)
        }
        return copy
    }

    /// 平移（保持大小，位移量被限制在長圖內）。
    public func moved(dx: CGFloat, dy: CGFloat, canvasHeightRatio h: CGFloat) -> Annotation {
        let b = bounds
        let h = Self.height(h)
        let ddx = min(max(dx, -b.minX), max(1 - b.maxX, -b.minX))
        let ddy = min(max(dy, -b.minY), max(h - b.maxY, -b.minY))
        var copy = self
        switch shape {
        case let .text(r, t, s): copy.shape = .text(rect: r.offsetBy(dx: ddx, dy: ddy), text: t, style: s)
        case let .rectangle(r, s): copy.shape = .rectangle(rect: r.offsetBy(dx: ddx, dy: ddy), style: s)
        case let .mosaic(r): copy.shape = .mosaic(rect: r.offsetBy(dx: ddx, dy: ddy))
        case let .image(r, img): copy.shape = .image(rect: r.offsetBy(dx: ddx, dy: ddy), image: img)
        case let .arrow(a, e, s):
            copy.shape = .arrow(start: CGPoint(x: a.x + ddx, y: a.y + ddy),
                                end: CGPoint(x: e.x + ddx, y: e.y + ddy), style: s)
        }
        return copy
    }

    /// 縮放矩形類標記（箭頭不變）。
    public func resized(to rect: CGRect, canvasHeightRatio h: CGFloat) -> Annotation {
        var copy = self
        let r = Self.clamp(rect, h)
        switch shape {
        case let .text(_, t, s): copy.shape = .text(rect: r, text: t, style: s)
        case let .rectangle(_, s): copy.shape = .rectangle(rect: r, style: s)
        case let .mosaic: copy.shape = .mosaic(rect: r)
        case let .image(_, img): copy.shape = .image(rect: r, image: img)
        case .arrow: break
        }
        return copy
    }

    /// 調整箭頭端點（非箭頭不變）。
    public func resized(start: CGPoint, end: CGPoint, canvasHeightRatio h: CGFloat) -> Annotation {
        guard case let .arrow(_, _, s) = shape else { return self }
        var copy = self
        let (a, b) = Self.clamp(start: start, end: end, h)
        copy.shape = .arrow(start: a, end: b, style: s)
        return copy
    }

    private static func height(_ h: CGFloat) -> CGFloat { max(h, AnnotationLimits.minSize) }

    private static func clamp(_ rect: CGRect, _ canvasH: CGFloat) -> CGRect {
        let h = height(canvasH)
        let r = rect.standardized
        let w = min(max(r.width, AnnotationLimits.minSize), 1)
        let ht = min(max(r.height, AnnotationLimits.minSize), h)
        let x = min(max(r.minX, 0), 1 - w)
        let y = min(max(r.minY, 0), h - ht)
        return CGRect(x: x, y: y, width: w, height: ht)
    }

    /// 圖片用：保持長寬比，過大則等比縮小（不小於最小尺寸），再平移進長圖。
    private static func clampKeepingAspect(_ rect: CGRect, _ canvasH: CGFloat) -> CGRect {
        let h = height(canvasH)
        let r = rect.standardized
        guard r.width > 0, r.height > 0 else { return clamp(r, canvasH) }
        let down = min(1, 1 / r.width, h / r.height)
        let up = max(1, AnnotationLimits.minSize / min(r.width, r.height))
        let k = down < 1 ? down : up
        let w = r.width * k, ht = r.height * k
        return CGRect(x: min(max(r.minX, 0), max(1 - w, 0)), y: min(max(r.minY, 0), max(h - ht, 0)), width: w, height: ht)
    }

    private static func clamp(start: CGPoint, end: CGPoint, _ canvasH: CGFloat) -> (CGPoint, CGPoint) {
        let h = height(canvasH)
        func c(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), h)) }
        let a = c(start)
        var b = c(end)
        let len = hypot(b.x - a.x, b.y - a.y)
        if len < AnnotationLimits.minSize {
            // 退化為最小長度：優先往右，放不下則往左
            let dx = a.x + AnnotationLimits.minSize <= 1 ? AnnotationLimits.minSize : -AnnotationLimits.minSize
            b = CGPoint(x: a.x + dx, y: a.y)
        }
        return (a, b)
    }
}

/// 標記清單：由下而上的 z 順序（最後者在最上），含撤銷堆疊。
public struct AnnotationList {
    public private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }

    public func annotation(id: Annotation.ID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// 記錄目前狀態供撤銷。手勢（拖曳）開始時呼叫一次，其後以 `recordUndo: false` 更新，整段手勢即為一次撤銷。
    public mutating func checkpoint() { undoStack.append(annotations) }

    /// 夾限後加入，位於最上。回傳實際加入（夾限後）的標記。
    @discardableResult
    public mutating func add(_ annotation: Annotation, canvasHeightRatio: CGFloat,
                             recordUndo: Bool = true) -> Annotation {
        if recordUndo { checkpoint() }
        let clamped = annotation.clamped(canvasHeightRatio: canvasHeightRatio)
        annotations.append(clamped)
        return clamped
    }

    /// 以閉包修改（樣式、文字…）；不夾限幾何。找不到 id 回傳 false。
    @discardableResult
    public mutating func update(id: Annotation.ID, recordUndo: Bool = true,
                                _ body: (inout Annotation) -> Void) -> Bool {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return false }
        if recordUndo { checkpoint() }
        body(&annotations[i])
        return true
    }

    @discardableResult
    public mutating func move(id: Annotation.ID, dx: CGFloat, dy: CGFloat, canvasHeightRatio: CGFloat,
                              recordUndo: Bool = true) -> Bool {
        update(id: id, recordUndo: recordUndo) { $0 = $0.moved(dx: dx, dy: dy, canvasHeightRatio: canvasHeightRatio) }
    }

    @discardableResult
    public mutating func resize(id: Annotation.ID, to rect: CGRect, canvasHeightRatio: CGFloat,
                                recordUndo: Bool = true) -> Bool {
        update(id: id, recordUndo: recordUndo) { $0 = $0.resized(to: rect, canvasHeightRatio: canvasHeightRatio) }
    }

    @discardableResult
    public mutating func resize(id: Annotation.ID, start: CGPoint, end: CGPoint, canvasHeightRatio: CGFloat,
                                recordUndo: Bool = true) -> Bool {
        update(id: id, recordUndo: recordUndo) {
            $0 = $0.resized(start: start, end: end, canvasHeightRatio: canvasHeightRatio)
        }
    }

    @discardableResult
    public mutating func remove(id: Annotation.ID, recordUndo: Bool = true) -> Bool {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return false }
        if recordUndo { checkpoint() }
        annotations.remove(at: i)
        return true
    }

    /// 撤銷最近一次操作；無可撤銷時無作用並回傳 false。
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        annotations = previous
        return true
    }

    /// 清除全部標記與撤銷堆疊（UI 在 `ComposeList.clear()` 時一併呼叫）。
    public mutating func clear() {
        annotations.removeAll()
        undoStack.removeAll()
    }
}
