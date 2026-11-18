import CoreGraphics
import Foundation

public enum AnnotationHandle: Equatable, Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case arrowStart, arrowEnd
}

/// 標記互動的純幾何（螢幕座標 ↔ 正規化座標、把手與命中判斷）。座標皆為長圖寬度正規化，容差亦同。
public enum AnnotationGeometry {
    /// 畫布內的點（左上原點，單位為顯示點數）→ 正規化座標。
    public static func normalize(_ point: CGPoint, canvasWidth: CGFloat) -> CGPoint {
        guard canvasWidth > 0 else { return .zero }
        return CGPoint(x: point.x / canvasWidth, y: point.y / canvasWidth)
    }

    /// 正規化座標 → 畫布內的點。
    public static func denormalize(_ point: CGPoint, canvasWidth: CGFloat) -> CGPoint {
        CGPoint(x: point.x * canvasWidth, y: point.y * canvasWidth)
    }

    public static func denormalize(_ rect: CGRect, canvasWidth: CGFloat) -> CGRect {
        CGRect(x: rect.minX * canvasWidth, y: rect.minY * canvasWidth,
               width: rect.width * canvasWidth, height: rect.height * canvasWidth)
    }

    /// 兩點拖曳出的矩形（不論方向）。
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// 把手位置：矩形類為四角與四邊中點；箭頭為兩端點。
    public static func handles(for annotation: Annotation) -> [(handle: AnnotationHandle, point: CGPoint)] {
        if case let .arrow(s, e, _) = annotation.shape {
            return [(.arrowStart, s), (.arrowEnd, e)]
        }
        let r = annotation.bounds
        return [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
    }

    /// 點是否落在某個把手容差內；多個重疊時取最近者。
    public static func hitHandle(_ annotation: Annotation, at p: CGPoint, tolerance: CGFloat) -> AnnotationHandle? {
        handles(for: annotation)
            .map { ($0.handle, hypot($0.point.x - p.x, $0.point.y - p.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// 拖動矩形把手到 `p` 後的矩形（可翻轉；尺寸夾限交給 `Annotation.resized`）。
    public static func resizedRect(_ rect: CGRect, dragging handle: AnnotationHandle, to p: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        case .arrowStart, .arrowEnd: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// 點擊命中的最上層標記（z 順序後者在上）。箭頭以到線段距離判斷，其餘以外框（含容差）。
    public static func hitTest(_ annotations: [Annotation], at p: CGPoint, tolerance: CGFloat) -> Annotation.ID? {
        for a in annotations.reversed() {
            switch a.shape {
            case let .arrow(s, e, style):
                if distance(from: p, toSegment: s, e) <= tolerance + CGFloat(style.width) / 2 { return a.id }
            default:
                if a.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) { return a.id }
            }
        }
        return nil
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
