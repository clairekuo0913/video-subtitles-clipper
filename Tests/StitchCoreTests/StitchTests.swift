import XCTest
import ImageIO
@testable import StitchCore

/// 上半（y 由上往下前 half 列）紅、其餘藍。
private func twoToneImage(width: Int, height: Int, redRows: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: height - redRows, width: width, height: redRows))
    return ctx.makeImage()!
}

final class CropBandTests: XCTestCase {
    func testDefault() {
        XCTAssertEqual(CropBand.default.top, 0.85, accuracy: 1e-9)
        XCTAssertEqual(CropBand.default.bottom, 1.0, accuracy: 1e-9)
    }

    func testInitClampsAndKeepsInvariant() {
        var b = CropBand(top: -1, bottom: 5)
        XCTAssertEqual([b.top, b.bottom], [0, 1])
        b = CropBand(top: 0.6, bottom: 0.3) // 上 >= 下
        XCTAssertEqual(b.bottom - b.top, CropBand.minHeight, accuracy: 1e-9)
        XCTAssertLessThan(b.top, b.bottom)
        b = CropBand(top: 1.0, bottom: 1.0)
        XCTAssertEqual(b.bottom, 1.0, accuracy: 1e-9)
        XCTAssertEqual(b.top, 1.0 - CropBand.minHeight, accuracy: 1e-9)
    }

    func testMinHeightIs002() {
        XCTAssertEqual(CropBand.minHeight, 0.02, accuracy: 1e-12)
    }

    func testMovingTopClampsToMinHeightAndZero() {
        let b = CropBand(top: 0.5, bottom: 0.8)
        XCTAssertEqual(b.movingTop(to: 0.79).top, 0.78, accuracy: 1e-9)
        XCTAssertEqual(b.movingTop(to: 2).top, 0.78, accuracy: 1e-9)
        XCTAssertEqual(b.movingTop(to: -1).top, 0, accuracy: 1e-9)
        XCTAssertEqual(b.movingTop(to: 0.1).bottom, 0.8, accuracy: 1e-9)
    }

    func testMovingBottomClampsToMinHeightAndOne() {
        let b = CropBand(top: 0.5, bottom: 0.8)
        XCTAssertEqual(b.movingBottom(to: 0.51).bottom, 0.52, accuracy: 1e-9)
        XCTAssertEqual(b.movingBottom(to: -1).bottom, 0.52, accuracy: 1e-9)
        XCTAssertEqual(b.movingBottom(to: 3).bottom, 1.0, accuracy: 1e-9)
        XCTAssertEqual(b.movingBottom(to: 0.9).top, 0.5, accuracy: 1e-9)
    }

    func testRowsRoundingAndBounds() {
        XCTAssertEqual(CropBand.default.rows(imageHeight: 1000), 850..<1000)
        // 110 * 0.85 = 93.5 -> 94（.5 進位）
        XCTAssertEqual(CropBand.default.rows(imageHeight: 110), 94..<110)
        XCTAssertEqual(CropBand(top: 0.7, bottom: 0.9).rows(imageHeight: 100), 70..<90)
        // 至少 1 px、不越界
        let tiny = CropBand(top: 0.98, bottom: 1.0).rows(imageHeight: 10)
        XCTAssertEqual(tiny.count, 1)
        XCTAssertLessThanOrEqual(tiny.upperBound, 10)
        XCTAssertEqual(CropBand.default.rows(imageHeight: 1), 0..<1)
    }

    func testCropSameRatioAcrossResolutions() throws {
        for (w, h) in [(1280, 720), (2560, 1440), (390, 844)] {
            let band = CropBand(top: 0.5, bottom: 0.75)
            let c = try XCTUnwrap(SubtitleCrop.crop(solidImage(width: w, height: h), band: band))
            XCTAssertEqual(c.width, w)
            XCTAssertEqual(c.height, band.rows(imageHeight: h).count)
        }
    }

    func testDraggingBottomExcludesBottomMargin() throws {
        // 100 列：0..<70 紅、70..<90 藍（字幕）、90..<100 紅（底部留白）
        let ctx = CGContext(data: nil, width: 4, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 10, width: 4, height: 20)) // y 由上 70..<90
        let c = try XCTUnwrap(SubtitleCrop.crop(ctx.makeImage()!, band: CropBand(top: 0.7, bottom: 0.9)))
        XCTAssertEqual(c.height, 20)
        XCTAssertEqual(pixel(c, x: 0, y: 0).2, 255)
        XCTAssertEqual(pixel(c, x: 0, y: 19).2, 255)
        XCTAssertEqual(pixel(c, x: 0, y: 0).0, 0)
    }
}

final class StitcherTests: XCTestCase {
    private let half = CropBand(top: 0.5, bottom: 1.0)

    private func build(_ specs: [(Int, Int)], frames: Set<Int> = [0]) -> ComposeList {
        var l = ComposeList()
        var ids: [UUID] = []
        for (i, s) in specs.enumerated() {
            ids.append(l.append(image: solidImage(width: s.0, height: s.1), name: "n\(i)").id)
        }
        for i in frames where i != 0 { _ = l.setKind(id: ids[i], to: .frame) }
        return l
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(Stitcher.stitch(ComposeList(), band: .default))
    }

    func testSingleSceneSeamlessSameWidth() throws {
        // 1 frame 400 + 3 subtitles(各 100 * 0.25 = 25)
        let l = build([(100, 400), (100, 100), (100, 100), (100, 100)])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: CropBand(top: 0.75, bottom: 1.0)))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 400 + 3 * 25)
    }

    func testSeamlessNoGapBetweenRows() throws {
        var l = ComposeList()
        l.append(image: solidImage(width: 10, height: 10, r: 255, g: 0, b: 0), name: "f")
        l.append(image: solidImage(width: 10, height: 10, r: 0, g: 0, b: 255), name: "s")
        let out = try XCTUnwrap(Stitcher.stitch(l, band: half)) // 10 + 5
        XCTAssertEqual(out.height, 15)
        XCTAssertEqual(pixel(out, x: 0, y: 9).0, 255)
        XCTAssertEqual(pixel(out, x: 0, y: 10).2, 255)
    }

    func testMultiSceneIsSeamlessToo() throws {
        // 場景一: frame 100 + sub 50；場景二: frame 100（幕間無間隔）
        var l = ComposeList()
        l.append(image: solidImage(width: 10, height: 100, r: 255, g: 0, b: 0), name: "f1")
        l.append(image: solidImage(width: 10, height: 100, r: 0, g: 0, b: 255), name: "s1")
        let f2 = l.append(image: solidImage(width: 10, height: 100, r: 0, g: 255, b: 0), name: "f2")
        _ = l.setKind(id: f2.id, to: .frame)
        let out = try XCTUnwrap(Stitcher.stitch(l, band: half))
        XCTAssertEqual(out.height, 100 + 50 + 100)
        XCTAssertEqual(pixel(out, x: 5, y: 149).2, 255)  // 字幕最後一列
        XCTAssertEqual(pixel(out, x: 5, y: 150).1, 255)  // 第二幕 frame 緊接
    }

    func testSubtitleUsesBandRows() throws {
        // 第二張 100 列：0..<70 紅、70..<100 藍；band 0.7–0.9 只取藍的前 20 列
        var l = ComposeList()
        l.append(image: solidImage(width: 10, height: 10, r: 0, g: 255, b: 0), name: "f")
        l.append(image: twoToneImage(width: 10, height: 100, redRows: 70), name: "s")
        let out = try XCTUnwrap(Stitcher.stitch(l, band: CropBand(top: 0.7, bottom: 0.9)))
        XCTAssertEqual(out.height, 10 + 20)
        XCTAssertEqual(pixel(out, x: 5, y: 10).2, 255)
        XCTAssertEqual(pixel(out, x: 5, y: 29).2, 255)
    }

    func testCanvasIsOpaqueBlack() throws {
        let canvas = try XCTUnwrap(Stitcher.makeCanvas(width: 6, height: 4))
        let img = try XCTUnwrap(canvas.makeImage())
        for (x, y) in [(0, 0), (5, 3), (2, 2)] {
            let p = pixel(img, x: x, y: y)
            XCTAssertEqual([p.0, p.1, p.2, p.3], [0, 0, 0, 255])
        }
    }

    func testDifferentWidthScaledProportionally() throws {
        let l = build([(200, 100), (100, 80)], frames: [0, 1])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: .default))
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 100 + 160)
    }

    func testDifferentWidthSubtitleCroppedThenScaled() throws {
        // 第二張 100x200，band 0.75–1.0 -> 50 高 -> 放大 2x 為 100
        let l = build([(200, 100), (100, 200)])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: CropBand(top: 0.75, bottom: 1.0)))
        XCTAssertEqual(out.height, 100 + 100)
    }

    func testSameWidthNotScaledRetina() throws {
        let l = build([(2880, 1800), (2880, 1800)])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: .default))
        XCTAssertEqual(out.width, 2880)
        XCTAssertEqual(out.height, 1800 + 270)
    }

    func testSameWidthPixelsPreserved() throws {
        let l = build([(8, 8)])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: .default))
        let p = pixel(out, x: 3, y: 3)
        XCTAssertEqual([p.0, p.1, p.2, p.3], [255, 0, 0, 255])
    }

    func testOutputScaleAppliedToStitchedResult() throws {
        let l = build([(100, 400)])
        let out = try XCTUnwrap(Stitcher.stitch(l, band: .default, outputScale: .percent50))
        XCTAssertEqual(out.width, 50)
        XCTAssertEqual(out.height, 200)
    }
}

final class OutputScaleTests: XCTestCase {
    func testDefaultIs100() {
        XCTAssertEqual(OutputScale.default, .percent100)
        XCTAssertEqual(OutputScale.allCases.map(\.percent), [25, 50, 75, 100])
    }

    func test50PercentHalvesSize() throws {
        let out = OutputScale.percent50.apply(to: solidImage(width: 2000, height: 3000))
        XCTAssertEqual(out.width, 1000)
        XCTAssertEqual(out.height, 1500)
    }

    func test100PercentReturnsSameImage() {
        let img = solidImage(width: 20, height: 30)
        XCTAssertTrue(OutputScale.percent100.apply(to: img) === img)
    }

    func testRoundingAndMinimumOnePixel() {
        XCTAssertEqual(OutputScale.percent25.size(width: 10, height: 10).width, 3)  // 2.5 -> 3
        XCTAssertEqual(OutputScale.percent25.size(width: 1, height: 1).width, 1)
        let tiny = OutputScale.percent25.apply(to: solidImage(width: 2, height: 1))
        XCTAssertEqual(tiny.width, 1)
        XCTAssertEqual(tiny.height, 1)
        XCTAssertEqual(OutputScale.percent75.size(width: 101, height: 3).width, 76) // 75.75
    }
}

final class CropBandGeometryTests: XCTestCase {
    func testYToRatioAndBack() {
        XCTAssertEqual(CropBandGeometry.ratio(forY: 150, displayHeight: 600, zoom: 1), 0.25, accuracy: 1e-9)
        XCTAssertEqual(CropBandGeometry.y(forRatio: 0.25, displayHeight: 600, zoom: 1), 150, accuracy: 1e-9)
    }

    func testRatioIndependentOfZoom() {
        for zoom in [0.25, 1.0, 4.0] {
            let y = 0.4 * 600 * zoom
            XCTAssertEqual(CropBandGeometry.ratio(forY: y, displayHeight: 600, zoom: zoom), 0.4, accuracy: 1e-9)
            XCTAssertEqual(CropBandGeometry.y(forRatio: 0.4, displayHeight: 600, zoom: zoom), y, accuracy: 1e-9)
        }
    }

    func testRatioClampedTo01() {
        XCTAssertEqual(CropBandGeometry.ratio(forY: -50, displayHeight: 600, zoom: 2), 0)
        XCTAssertEqual(CropBandGeometry.ratio(forY: 99999, displayHeight: 600, zoom: 2), 1)
    }

    func testDragEdgesProduceBandAtAnyZoom() {
        for zoom in [0.25, 1.0, 4.0] {
            let h = 600 * zoom
            var band = CropBand.default
            band = band.movingTop(to: CropBandGeometry.ratio(forY: 0.5 * h, displayHeight: 600, zoom: zoom))
            band = band.movingBottom(to: CropBandGeometry.ratio(forY: 0.9 * h, displayHeight: 600, zoom: zoom))
            XCTAssertEqual(band.top, 0.5, accuracy: 1e-9)
            XCTAssertEqual(band.bottom, 0.9, accuracy: 1e-9)
        }
    }

    func testDegenerateHeightReturnsZero() {
        XCTAssertEqual(CropBandGeometry.ratio(forY: 10, displayHeight: 0, zoom: 1), 0)
    }
}

final class PNGOutputTests: XCTestCase {
    func testEncodeDecodesToSameSize() throws {
        let data = try XCTUnwrap(PNGOutput.encode(solidImage(width: 37, height: 21)))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 37)
        XCTAssertEqual(img.height, 21)
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testFilenameFormat() {
        let tz = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        XCTAssertEqual(PNGOutput.filename(for: date, timeZone: tz), "subtitles-20231114-221320.png")
    }

    func testStitchedOutputEncodesToExpectedSize() throws {
        var l = ComposeList()
        l.append(image: solidImage(width: 50, height: 40), name: "a")
        l.append(image: solidImage(width: 50, height: 40), name: "b")
        let out = try XCTUnwrap(Stitcher.stitch(l, band: CropBand(top: 0.5, bottom: 1.0)))
        let data = try XCTUnwrap(PNGOutput.encode(out))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 50)
        XCTAssertEqual(img.height, 60)
    }
}
