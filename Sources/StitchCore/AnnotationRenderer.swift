import CoreGraphics
import CoreText
import Foundation

/// 把標記畫到影像上；預覽與輸出共用。座標與尺寸一律由「底圖寬度（像素）」換算：
/// 倍率 50% 時先在 100% 畫好再整張縮放（見 `Stitcher`），故相對位置與比例天然不變。
public enum AnnotationRenderer {
    /// 馬賽克區塊邊長相對底圖寬度。
    public static let mosaicBlockRatio: CGFloat = 0.02

    public static func mosaicBlockSize(width: Int) -> Int {
        max(2, Int((CGFloat(width) * mosaicBlockRatio).rounded()))
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 底圖 + 全部標記（馬賽克先、其餘依 z 順序）。無標記時仍回傳重繪結果。
    public static func render(onto base: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let ctx = makeContext(width: base.width, height: base.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        ctx.draw(base, in: rect)
        drawMosaics(annotations, base: base, in: ctx)
        draw(annotations, in: ctx, width: base.width, height: base.height)
        return ctx.makeImage()
    }

    /// 預覽用透明覆蓋層，尺寸同 `base`：馬賽克區域含（區塊化後的）底圖內容，其餘標記為繪製結果，其他處全透明。
    /// 疊在同尺寸（或等比縮放）底圖上即等於 `render`。`base` 可為縮圖，所有尺寸皆依其寬度換算。
    public static func overlay(for base: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let ctx = makeContext(width: base.width, height: base.height) else { return nil }
        drawMosaics(annotations, base: base, in: ctx)
        draw(annotations, in: ctx, width: base.width, height: base.height)
        return ctx.makeImage()
    }

    /// 於既有 context 繪製「非馬賽克」標記。`width`/`height` 為 context 像素尺寸（原點在左下）。
    public static func draw(_ annotations: [Annotation], in ctx: CGContext, width: Int, height: Int) {
        let w = CGFloat(width), h = CGFloat(height)
        func px(_ r: CGRect) -> CGRect { CGRect(x: r.minX * w, y: h - r.maxY * w, width: r.width * w, height: r.height * w) }
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: h - p.y * w) }

        for a in annotations {
            ctx.saveGState()
            switch a.shape {
            case .mosaic: break
            case let .rectangle(r, s):
                let lw = max(1, CGFloat(s.width) * w)
                ctx.setStrokeColor(s.color.cgColor)
                ctx.setLineWidth(lw)
                ctx.stroke(px(r))
            case let .arrow(start, end, s):
                drawArrow(ctx, from: pt(start), to: pt(end), width: max(1, CGFloat(s.width) * w), color: s.color.cgColor)
            case let .image(r, image):
                ctx.interpolationQuality = .high
                ctx.draw(image, in: px(r))
            case let .text(r, text, s):
                drawText(ctx, rect: px(r), text: text, style: s, canvasWidth: w)
            }
            ctx.restoreGState()
        }
    }

    // MARK: 箭頭

    private static func drawArrow(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width lw: CGFloat, color: CGColor) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let headLen = min(lw * 5, len), halfW = lw * 2.5
        let base = CGPoint(x: b.x - ux * headLen, y: b.y - uy * headLen)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.butt)
        ctx.move(to: a)
        ctx.addLine(to: base)
        ctx.strokePath()
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: base.x - uy * halfW, y: base.y + ux * halfW))
        ctx.addLine(to: CGPoint(x: base.x + uy * halfW, y: base.y - ux * halfW))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: 文字

    private static func drawText(_ ctx: CGContext, rect: CGRect, text: String, style s: TextStyle, canvasWidth w: CGFloat) {
        if let fill = s.fillColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(rect)
        }
        let fontSize = max(1, CGFloat(s.fontSize) * w)
        if let border = s.border {
            let bw = max(1, CGFloat(border.width) * w)
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(bw)
            ctx.stroke(rect.insetBy(dx: bw / 2, dy: bw / 2))
        }
        guard !text.isEmpty else { return }
        let padding = fontSize * 0.25
        let textRect = rect.insetBy(dx: padding, dy: padding)
        guard textRect.width > 0, textRect.height > 0 else { return }

        let font = CTFontCreateUIFontForLanguage(s.bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: s.textColor.cgColor,
        ]
        let str = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(str)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: textRect, transform: nil), nil)
        ctx.clip(to: rect)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
    }

    // MARK: 馬賽克

    /// 對 `ctx`（與 `base` 同尺寸、原點左下）內的馬賽克區域，以 `base` 內容縮小再最近鄰放大覆蓋。
    private static func drawMosaics(_ annotations: [Annotation], base: CGImage, in ctx: CGContext) {
        let w = CGFloat(base.width), imgH = base.height
        let block = mosaicBlockSize(width: base.width)
        for a in annotations {
            guard case let .mosaic(r) = a.shape else { continue }
            // 像素矩形（由上往下），取整並夾在影像內
            let x0 = max(0, Int((r.minX * w).rounded())), y0 = max(0, Int((r.minY * w).rounded()))
            let x1 = min(base.width, Int((r.maxX * w).rounded())), y1 = min(imgH, Int((r.maxY * w).rounded()))
            guard x1 > x0, y1 > y0,
                  let crop = base.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { continue }
            let rw = x1 - x0, rh = y1 - y0
            let sw = (rw + block - 1) / block, sh = (rh + block - 1) / block
            guard let small = makeContext(width: sw, height: sh) else { continue }
            small.interpolationQuality = .high
            small.draw(crop, in: CGRect(x: 0, y: CGFloat(sh) - CGFloat(rh) / CGFloat(block),
                                        width: CGFloat(rw) / CGFloat(block), height: CGFloat(rh) / CGFloat(block)))
            guard let tiny = small.makeImage() else { continue }
            let target = CGRect(x: x0, y: imgH - y1, width: rw, height: rh)
            ctx.saveGState()
            ctx.clip(to: target)
            ctx.interpolationQuality = .none
            ctx.draw(tiny, in: CGRect(x: CGFloat(x0), y: CGFloat(imgH - y0 - sh * block),
                                      width: CGFloat(sw * block), height: CGFloat(sh * block)))
            ctx.restoreGState()
        }
    }
}
