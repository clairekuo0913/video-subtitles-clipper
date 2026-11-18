import XCTest
import CoreGraphics
@testable import StitchCore

private func rgba(_ image: CGImage) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ctx = CGContext(data: &buf, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buf
}

/// 水平條紋 + 垂直漸層，使馬賽克前後可區分。
private func patternImage(width: Int, height: Int) -> CGImage {
    var buf = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        buf[i] = UInt8((x * 7) % 256); buf[i + 1] = UInt8((y * 13) % 256); buf[i + 2] = UInt8(((x + y) * 5) % 256); buf[i + 3] = 255
    } }
    let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

final class AnnotationRendererTests: XCTestCase {
    private func red(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.0 > 200 && p.1 < 60 && p.2 < 60 }
    private func white(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.0 > 240 && p.1 > 240 && p.2 > 240 }
    private func black(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.0 < 15 && p.1 < 15 && p.2 < 15 }

    private let line = LineStyle(color: .red, width: 0.02) // 寬 200 → 4 px

    // MARK: 2.1 rectangle & arrow

    func testRectangleStrokePositionAndColor() throws {
        let base = solidImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let ann = Annotation(shape: .rectangle(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), style: line))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        XCTAssertEqual(out.width, 200); XCTAssertEqual(out.height, 200)
        XCTAssertTrue(red(pixel(out, x: 50, y: 100)))   // 左邊緣
        XCTAssertTrue(red(pixel(out, x: 150, y: 100)))  // 右邊緣
        XCTAssertTrue(red(pixel(out, x: 100, y: 50)))   // 上邊緣
        XCTAssertTrue(red(pixel(out, x: 100, y: 150)))  // 下邊緣
        XCTAssertTrue(white(pixel(out, x: 100, y: 100))) // 內部未填
        XCTAssertTrue(white(pixel(out, x: 20, y: 20)))   // 外部不變
    }

    func testRectangleLineWidthRelativeToCanvasWidth() throws {
        let base = solidImage(width: 400, height: 400, r: 255, g: 255, b: 255)
        let ann = Annotation(shape: .rectangle(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), style: line))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        // 線寬 0.02*400 = 8 px，以 x=100 為中心 → 96..104
        XCTAssertTrue(red(pixel(out, x: 97, y: 200)))
        XCTAssertTrue(red(pixel(out, x: 102, y: 200)))
        XCTAssertTrue(white(pixel(out, x: 93, y: 200)))
        XCTAssertTrue(white(pixel(out, x: 107, y: 200)))
    }

    func testArrowLineAndHead() throws {
        let base = solidImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let ann = Annotation(shape: .arrow(start: CGPoint(x: 0.1, y: 0.5), end: CGPoint(x: 0.9, y: 0.5), style: line))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        XCTAssertTrue(red(pixel(out, x: 40, y: 100)))    // 線身
        XCTAssertTrue(red(pixel(out, x: 20, y: 100)))    // 起點附近
        XCTAssertTrue(red(pixel(out, x: 170, y: 100)))   // 箭頭頭部附近（終點 180）
        XCTAssertTrue(red(pixel(out, x: 160, y: 108)))   // 頭部比線身寬
        XCTAssertTrue(white(pixel(out, x: 40, y: 108)))  // 線身外不變
        XCTAssertTrue(white(pixel(out, x: 195, y: 100))) // 終點之後不變
        XCTAssertTrue(white(pixel(out, x: 5, y: 100)))
    }

    func testScale50KeepsRelativePositionViaStitcher() throws {
        var list = ComposeList()
        list.append(image: solidImage(width: 200, height: 200, r: 255, g: 255, b: 255), name: "a")
        let ann = Annotation(shape: .rectangle(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), style: line))
        let full = try XCTUnwrap(Stitcher.stitch(list, band: .default, outputScale: .percent100, annotations: [ann]))
        let half = try XCTUnwrap(Stitcher.stitch(list, band: .default, outputScale: .percent50, annotations: [ann]))
        XCTAssertEqual(half.width, 100)
        XCTAssertTrue(red(pixel(full, x: 50, y: 100)))
        XCTAssertTrue(red(pixel(half, x: 25, y: 50)))    // 左邊緣比例相同
        XCTAssertTrue(red(pixel(half, x: 75, y: 50)))
        XCTAssertTrue(red(pixel(half, x: 50, y: 25)))
        XCTAssertTrue(white(pixel(half, x: 50, y: 50)))
        XCTAssertTrue(white(pixel(half, x: 10, y: 10)))
    }

    // MARK: 2.2 mosaic

    func testMosaicBlocksInsideAndUntouchedOutside() throws {
        let base = patternImage(width: 200, height: 200)
        let ann = Annotation(shape: .mosaic(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        let b = AnnotationRenderer.mosaicBlockSize(width: 200)
        XCTAssertGreaterThan(b, 1)
        let a = rgba(base), o = rgba(out)
        func px(_ buf: [UInt8], _ x: Int, _ y: Int) -> [UInt8] { Array(buf[(y * 200 + x) * 4..<(y * 200 + x) * 4 + 4]) }
        // 區域外逐像素不變
        for (x, y) in [(10, 10), (49, 100), (151, 100), (100, 49), (100, 151), (199, 199)] {
            XCTAssertEqual(px(a, x, y), px(o, x, y), "outside \(x),\(y)")
        }
        // 區域內：同一區塊內像素相同（區塊自區域左上 (50,50) 起算）
        for (bx, by) in [(0, 0), (1, 1), (3, 2)] {
            let x0 = 50 + bx * b, y0 = 50 + by * b
            let ref = px(o, x0, y0)
            XCTAssertEqual(px(o, x0 + b - 1, y0 + b - 1), ref)
            XCTAssertEqual(px(o, x0 + b / 2, y0), ref)
        }
        // 區域內已和原圖不同、且相鄰區塊不同
        XCTAssertNotEqual(px(a, 52, 53), px(o, 52, 53))
        XCTAssertNotEqual(px(o, 50, 50), px(o, 50 + b, 50 + b))
    }

    func testMosaicAppliedBeforeOtherAnnotations() throws {
        let base = patternImage(width: 200, height: 200)
        let mosaic = Annotation(shape: .mosaic(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        let rectAnn = Annotation(shape: .rectangle(rect: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), style: line))
        // 矩形先於馬賽克加入（z 較低），仍應在馬賽克之上可見
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [rectAnn, mosaic]))
        XCTAssertTrue(red(pixel(out, x: 60, y: 80)))
    }

    func testMosaicClampedRegionOutsideCanvasDoesNotCrash() throws {
        let base = patternImage(width: 100, height: 100)
        let ann = Annotation(shape: .mosaic(rect: CGRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5)))
        XCTAssertNotNil(AnnotationRenderer.render(onto: base, annotations: [ann]))
    }

    // MARK: 2.3 text

    func testTextNoFillShowsBackgroundAndTextColorPixels() throws {
        let base = solidImage(width: 400, height: 200, r: 255, g: 255, b: 255)
        let style = TextStyle(textColor: .red, fillColor: nil, fontSize: 0.1, bold: true, border: nil)
        let r = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
        let ann = Annotation(shape: .text(rect: r, text: "MMMM", style: style))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        let region = (40..<360, 20..<80)
        var redCount = 0, whiteCount = 0
        for y in region.1 { for x in region.0 {
            let p = pixel(out, x: x, y: y)
            if red(p) { redCount += 1 } else if white(p) { whiteCount += 1 }
        } }
        XCTAssertGreaterThan(redCount, 50)     // 文字色
        XCTAssertGreaterThan(whiteCount, 500)  // 無底色：背景透出
        XCTAssertTrue(white(pixel(out, x: 5, y: 5))) // 框外不變
    }

    func testTextFillCoversRectAndBorderDrawn() throws {
        let base = solidImage(width: 400, height: 200, r: 255, g: 255, b: 255)
        let style = TextStyle(textColor: .white, fillColor: .black, fontSize: 0.05, bold: false,
                              border: BorderStyle(color: .red, width: 0.02))
        let r = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.4)
        let ann = Annotation(shape: .text(rect: r, text: "", style: style))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        // rect 像素：x 40..360, y 80..240→（高 200，y 80..160）
        XCTAssertTrue(black(pixel(out, x: 200, y: 120)))  // 底色填滿
        XCTAssertTrue(red(pixel(out, x: 41, y: 120)))     // 邊框
        XCTAssertTrue(white(pixel(out, x: 20, y: 120)))   // 框外
    }

    func testTextWrapsInsideRect() throws {
        let base = solidImage(width: 400, height: 400, r: 255, g: 255, b: 255)
        let style = TextStyle(textColor: .red, fillColor: nil, fontSize: 0.08, bold: true, border: nil)
        let r = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.5) // 窄框，長字必換行
        let ann = Annotation(shape: .text(rect: r, text: "MMMMMMMMMMMMMMMMMMMM", style: style))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        func redIn(_ xs: Range<Int>, _ ys: Range<Int>) -> Bool {
            for y in ys { for x in xs where red(pixel(out, x: x, y: y)) { return true } }
            return false
        }
        XCTAssertTrue(redIn(40..<160, 40..<70))    // 第一行
        XCTAssertTrue(redIn(40..<160, 110..<200))  // 後續行（換行）
        XCTAssertFalse(redIn(165..<400, 0..<400))  // 不溢出右緣
    }

    func testBoldAndFontSizeAffectInk() throws {
        func ink(bold: Bool, size: CGFloat) throws -> Int {
            let base = solidImage(width: 400, height: 200, r: 255, g: 255, b: 255)
            let style = TextStyle(textColor: .red, fillColor: nil, fontSize: size, bold: bold, border: nil)
            let ann = Annotation(shape: .text(rect: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.8), text: "Hi", style: style))
            let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
            var n = 0
            for y in 0..<200 { for x in 0..<400 where !white(pixel(out, x: x, y: y)) { n += 1 } }
            return n
        }
        let small = try ink(bold: false, size: 0.05)
        let big = try ink(bold: false, size: 0.1)
        let bold = try ink(bold: true, size: 0.05)
        XCTAssertGreaterThan(big, small * 2)
        XCTAssertGreaterThan(bold, small)
    }

    // MARK: 預覽覆蓋層 API

    func testOverlayIsTransparentOutsideAndMatchesRenderWhenComposited() throws {
        let base = patternImage(width: 200, height: 200)
        let anns = [
            Annotation(shape: .mosaic(rect: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))),
            Annotation(shape: .rectangle(rect: CGRect(x: 0.3, y: 0.3, width: 0.5, height: 0.5), style: line)),
        ]
        let overlay = try XCTUnwrap(AnnotationRenderer.overlay(for: base, annotations: anns))
        XCTAssertEqual(overlay.width, 200)
        XCTAssertEqual(pixel(overlay, x: 190, y: 190).3, 0) // 無標記處全透明
        XCTAssertEqual(pixel(overlay, x: 30, y: 30).3, 255) // 馬賽克處不透明
        // 底圖 + 覆蓋層 == 直接輸出
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.draw(overlay, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let composed = try XCTUnwrap(ctx.makeImage())
        let direct = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: anns))
        XCTAssertEqual(rgba(composed), rgba(direct))
    }

    // MARK: 2.4 Stitcher integration

    func testStitcherWithoutAnnotationsIsPixelIdentical() throws {
        var list = ComposeList()
        list.append(image: solidImage(width: 20, height: 10, r: 255, g: 0, b: 0), name: "a")
        list.append(image: solidImage(width: 20, height: 8, r: 0, g: 0, b: 255), name: "b")
        let legacy = try XCTUnwrap(Stitcher.stitch(list, band: CropBand(top: 0, bottom: 1)))
        let withEmpty = try XCTUnwrap(Stitcher.stitch(list, band: CropBand(top: 0, bottom: 1), annotations: []))
        XCTAssertEqual(legacy.width, 20); XCTAssertEqual(legacy.height, 18)
        XCTAssertEqual(rgba(legacy), rgba(withEmpty))
        // 與手工期望一致：上 10 列紅、下 8 列藍
        var expected = [UInt8]()
        for y in 0..<18 { for _ in 0..<20 { expected += y < 10 ? [255, 0, 0, 255] : [0, 0, 255, 255] } }
        XCTAssertEqual(rgba(withEmpty), expected)
    }

    func testStitcherDrawsAnnotationsOnStitchedImageOnly() throws {
        var list = ComposeList()
        list.append(image: solidImage(width: 100, height: 100, r: 255, g: 255, b: 255), name: "a")
        let ann = Annotation(shape: .rectangle(rect: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
                                               style: LineStyle(color: .red, width: 0.04)))
        let plain = try XCTUnwrap(Stitcher.stitch(list, band: .default))
        let marked = try XCTUnwrap(Stitcher.stitch(list, band: .default, annotations: [ann]))
        XCTAssertEqual(marked.width, plain.width); XCTAssertEqual(marked.height, plain.height)
        XCTAssertTrue(red(pixel(marked, x: 20, y: 50)))
        XCTAssertTrue(white(pixel(plain, x: 20, y: 50)))
        XCTAssertTrue(white(pixel(marked, x: 90, y: 90)))
    }
}
