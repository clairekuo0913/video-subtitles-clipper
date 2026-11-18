import XCTest
import CoreGraphics
@testable import StitchCore

final class AnnotationImageTests: XCTestCase {
    private let blue = solidImage(width: 20, height: 10, r: 0, g: 0, b: 255)
    private func approx(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: 1.5 model

    func testKindAndBounds() {
        let a = Annotation(shape: .image(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15), image: blue))
        XCTAssertEqual(a.kind, .image)
        XCTAssertEqual(a.bounds, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15))
    }

    func testDefaultRectWidth30CenteredAtViewportCenter() {
        let r = AnnotationImagePlacement.defaultRect(canvasHeightRatio: 3, center: CGPoint(x: 0.5, y: 1.0), aspect: 2)
        approx(r, CGRect(x: 0.35, y: 1.0 - 0.075, width: 0.3, height: 0.15))
    }

    func testDefaultRectClampedInsideCanvas() {
        let r = AnnotationImagePlacement.defaultRect(canvasHeightRatio: 1, center: CGPoint(x: 0.99, y: 0.0), aspect: 2)
        approx(r, CGRect(x: 0.7, y: 0, width: 0.3, height: 0.15))
    }

    func testDefaultRectShrinksWhenCanvasTooShort() {
        // 畫布高 0.1，寬 0.3 的高 0.3（aspect 1）放不下 → 等比縮到高 0.1
        let r = AnnotationImagePlacement.defaultRect(canvasHeightRatio: 0.1, center: CGPoint(x: 0.5, y: 0.05), aspect: 1)
        approx(r, CGRect(x: 0.45, y: 0, width: 0.1, height: 0.1))
    }

    func testAspectLockedCornerResizeKeepsRatio() {
        let r = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.15)
        let out = AnnotationImagePlacement.resizedRect(r, dragging: .bottomRight, to: CGPoint(x: 0.8, y: 0.3), canvasHeightRatio: 1)
        approx(out, CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.3)) // 以較大變化量（寬）為準
    }

    func testAspectLockedResizeClampedToCanvas() {
        let r = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.15)
        let out = AnnotationImagePlacement.resizedRect(r, dragging: .bottomRight, to: CGPoint(x: 5, y: 5), canvasHeightRatio: 1)
        approx(out, CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.4))
        XCTAssertEqual(out.width / out.height, 2, accuracy: 1e-9)
    }

    func testAspectLockedResizeMinimumSize() {
        let r = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.15)
        let out = AnnotationImagePlacement.resizedRect(r, dragging: .bottomRight, to: CGPoint(x: 0.2, y: 0.2), canvasHeightRatio: 1)
        XCTAssertEqual(out.height, AnnotationLimits.minSize, accuracy: 1e-9)
        XCTAssertEqual(out.width / out.height, 2, accuracy: 1e-9)
        XCTAssertEqual(out.minX, 0.2, accuracy: 1e-9)
    }

    func testAspectLockedTopLeftAnchorsOppositeCorner() {
        let r = CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.15)
        let out = AnnotationImagePlacement.resizedRect(r, dragging: .topLeft, to: CGPoint(x: 0.1, y: 0.5), canvasHeightRatio: 1)
        XCTAssertEqual(out.maxX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(out.maxY, 0.55, accuracy: 1e-9)
        XCTAssertEqual(out.width / out.height, 2, accuracy: 1e-9)
        XCTAssertEqual(out.width, 0.6, accuracy: 1e-9)
    }

    func testAspectLockedEdgeResizeCentersOtherAxis() {
        let r = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.15)
        let out = AnnotationImagePlacement.resizedRect(r, dragging: .right, to: CGPoint(x: 0.8, y: 0), canvasHeightRatio: 1)
        approx(out, CGRect(x: 0.2, y: 0.125, width: 0.6, height: 0.3))
    }

    func testClampedImageKeepsAspectWhenOversized() {
        let a = Annotation(shape: .image(rect: CGRect(x: 0.5, y: 0.5, width: 2, height: 1), image: blue))
            .clamped(canvasHeightRatio: 1)
        XCTAssertEqual(a.bounds.width / a.bounds.height, 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(a.bounds.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(a.bounds.maxY, 1 + 1e-9)
        XCTAssertGreaterThanOrEqual(a.bounds.minX, 0)
    }

    func testListAddMoveResizeRemoveUndoForImage() {
        var list = AnnotationList()
        let a = Annotation(shape: .image(rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.15), image: blue))
        list.add(a, canvasHeightRatio: 1)
        XCTAssertEqual(list.annotations.count, 1)

        list.move(id: a.id, dx: 5, dy: 0, canvasHeightRatio: 1)           // 夾限在長圖內
        XCTAssertEqual(list.annotation(id: a.id)?.bounds.maxX ?? 9, 1, accuracy: 1e-9)

        let r = list.annotation(id: a.id)!.bounds
        let target = AnnotationImagePlacement.resizedRect(r, dragging: .bottomLeft, to: CGPoint(x: 0.5, y: 0.6), canvasHeightRatio: 1)
        list.resize(id: a.id, to: target, canvasHeightRatio: 1)
        let b = list.annotation(id: a.id)!.bounds
        XCTAssertEqual(b.width / b.height, 2, accuracy: 1e-9)

        XCTAssertTrue(list.undo())   // 撤銷縮放
        XCTAssertTrue(list.undo())   // 撤銷移動
        guard case let .image(_, img)? = list.annotation(id: a.id)?.shape else { return XCTFail() }
        XCTAssertTrue(img === blue)  // 快照持有同一個 CGImage 參考
        XCTAssertEqual(list.annotation(id: a.id)?.bounds, CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.15))

        list.remove(id: a.id)
        XCTAssertTrue(list.annotations.isEmpty)
        XCTAssertTrue(list.undo())
        XCTAssertEqual(list.annotations.count, 1)
        XCTAssertTrue(list.undo())   // 撤銷新增
        XCTAssertTrue(list.annotations.isEmpty)
        XCTAssertFalse(list.undo())
    }

    func testImageEquality() {
        let r = CGRect(x: 0, y: 0, width: 0.3, height: 0.15)
        let id = UUID()
        XCTAssertEqual(Annotation(id: id, shape: .image(rect: r, image: blue)), Annotation(id: id, shape: .image(rect: r, image: blue)))
        XCTAssertNotEqual(Annotation(id: id, shape: .image(rect: r, image: blue)),
                          Annotation(id: id, shape: .image(rect: r, image: solidImage(width: 20, height: 10))))
    }

    // MARK: 2.5 renderer

    private func isBlue(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.2 > 240 && p.0 < 15 && p.1 < 15 }
    private func isWhite(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.0 > 240 && p.1 > 240 && p.2 > 240 }
    private func isRed(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Bool { p.0 > 200 && p.1 < 60 && p.2 < 60 }

    func testRendererDrawsImagePositionAndSize() throws {
        let base = solidImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let ann = Annotation(shape: .image(rect: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), image: blue))
        let out = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [ann]))
        // 像素範圍 x 50..150、y 100..150
        XCTAssertTrue(isBlue(pixel(out, x: 52, y: 102)))
        XCTAssertTrue(isBlue(pixel(out, x: 147, y: 147)))
        XCTAssertTrue(isBlue(pixel(out, x: 100, y: 125)))
        XCTAssertTrue(isWhite(pixel(out, x: 46, y: 125)))
        XCTAssertTrue(isWhite(pixel(out, x: 154, y: 125)))
        XCTAssertTrue(isWhite(pixel(out, x: 100, y: 96)))
        XCTAssertTrue(isWhite(pixel(out, x: 100, y: 154)))
    }

    func testOverlayContainsImageAndTransparentElsewhere() throws {
        let base = solidImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let ann = Annotation(shape: .image(rect: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), image: blue))
        let ov = try XCTUnwrap(AnnotationRenderer.overlay(for: base, annotations: [ann]))
        XCTAssertTrue(isBlue(pixel(ov, x: 100, y: 125)))
        XCTAssertEqual(pixel(ov, x: 10, y: 10).3, 0)
    }

    func testImageScale50KeepsRelativePosition() throws {
        var list = ComposeList()
        list.append(image: solidImage(width: 200, height: 200, r: 255, g: 255, b: 255), name: "a")
        let ann = Annotation(shape: .image(rect: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), image: blue))
        let half = try XCTUnwrap(Stitcher.stitch(list, band: .default, outputScale: .percent50, annotations: [ann]))
        XCTAssertEqual(half.width, 100)
        XCTAssertTrue(isBlue(pixel(half, x: 50, y: 62)))
        XCTAssertTrue(isBlue(pixel(half, x: 27, y: 52)))
        XCTAssertTrue(isBlue(pixel(half, x: 72, y: 72)))
        XCTAssertTrue(isWhite(pixel(half, x: 22, y: 62)))
        XCTAssertTrue(isWhite(pixel(half, x: 78, y: 62)))
        XCTAssertTrue(isWhite(pixel(half, x: 50, y: 47)))
        XCTAssertTrue(isWhite(pixel(half, x: 50, y: 78)))
    }

    func testZOrderLaterAnnotationCoversImage() throws {
        let base = solidImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let img = Annotation(shape: .image(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25), image: blue))
        let rect = Annotation(shape: .rectangle(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25),
                                                style: LineStyle(color: .red, width: 0.02)))
        // 矩形在上：左邊緣（x=50）為紅
        let above = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [img, rect]))
        XCTAssertTrue(isRed(pixel(above, x: 50, y: 75)))
        XCTAssertTrue(isBlue(pixel(above, x: 100, y: 75)))
        // 圖片在上：圖片蓋住矩形邊緣內半部（x=52 在邊緣線內，圖片範圍 50..150）
        let below = try XCTUnwrap(AnnotationRenderer.render(onto: base, annotations: [rect, img]))
        XCTAssertTrue(isBlue(pixel(below, x: 52, y: 75)))
    }
}
