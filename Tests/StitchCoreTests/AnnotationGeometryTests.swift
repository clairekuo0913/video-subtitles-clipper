import CoreGraphics
import XCTest
@testable import StitchCore

final class AnnotationGeometryTests: XCTestCase {
    private func rectAnn(_ r: CGRect) -> Annotation { Annotation(shape: .rectangle(rect: r, style: .default)) }

    private func assertRect(_ a: CGRect, _ b: CGRect, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 1e-9, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 1e-9, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9, line: line)
    }

    func testNormalizeRoundTripAtDifferentZoom() {
        // 同一個正規化點在 25% 與 400% 寬度下換算回來一致
        let n = CGPoint(x: 0.25, y: 0.5)
        for w: CGFloat in [115, 460, 1840] {
            let screen = AnnotationGeometry.denormalize(n, canvasWidth: w)
            XCTAssertEqual(screen, CGPoint(x: 0.25 * w, y: 0.5 * w))
            let back = AnnotationGeometry.normalize(screen, canvasWidth: w)
            XCTAssertEqual(back.x, n.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, n.y, accuracy: 1e-9)
        }
        XCTAssertEqual(AnnotationGeometry.normalize(CGPoint(x: 5, y: 5), canvasWidth: 0), .zero)
    }

    func testRectFromAnyDirection() {
        let r = AnnotationGeometry.rect(from: CGPoint(x: 0.6, y: 0.5), to: CGPoint(x: 0.2, y: 0.1))
        assertRect(r, CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.4))
    }

    func testHandleCounts() {
        XCTAssertEqual(AnnotationGeometry.handles(for: rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))).count, 8)
        let arrow = Annotation(shape: .arrow(start: .zero, end: CGPoint(x: 0.3, y: 0.3), style: .default))
        XCTAssertEqual(AnnotationGeometry.handles(for: arrow).map(\.handle), [.arrowStart, .arrowEnd])
    }

    func testHitHandle() {
        let a = rectAnn(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2))
        XCTAssertEqual(AnnotationGeometry.hitHandle(a, at: CGPoint(x: 0.601, y: 0.399), tolerance: 0.01), .bottomRight)
        XCTAssertEqual(AnnotationGeometry.hitHandle(a, at: CGPoint(x: 0.4, y: 0.2), tolerance: 0.01), .top)
        XCTAssertNil(AnnotationGeometry.hitHandle(a, at: CGPoint(x: 0.4, y: 0.3), tolerance: 0.01))
    }

    func testResizedRect() {
        let r = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        assertRect(AnnotationGeometry.resizedRect(r, dragging: .right, to: CGPoint(x: 0.8, y: 0.9)), CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.2))
        assertRect(AnnotationGeometry.resizedRect(r, dragging: .topLeft, to: CGPoint(x: 0.1, y: 0.1)), CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3))
        // 拖過對邊會翻轉
        assertRect(AnnotationGeometry.resizedRect(r, dragging: .left, to: CGPoint(x: 0.8, y: 0)), CGRect(x: 0.6, y: 0.2, width: 0.2, height: 0.2))
    }

    func testHitTestTopmostAndMiss() {
        let below = rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        let above = rectAnn(CGRect(x: 0.3, y: 0.3, width: 0.5, height: 0.5))
        let list = [below, above]
        XCTAssertEqual(AnnotationGeometry.hitTest(list, at: CGPoint(x: 0.4, y: 0.4), tolerance: 0.005), above.id)
        XCTAssertEqual(AnnotationGeometry.hitTest(list, at: CGPoint(x: 0.15, y: 0.15), tolerance: 0.005), below.id)
        XCTAssertNil(AnnotationGeometry.hitTest(list, at: CGPoint(x: 0.95, y: 0.95), tolerance: 0.005))
    }

    func testHitTestArrowUsesSegmentDistance() {
        let arrow = Annotation(shape: .arrow(start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.9, y: 0.1), style: .default))
        XCTAssertEqual(AnnotationGeometry.hitTest([arrow], at: CGPoint(x: 0.5, y: 0.105), tolerance: 0.01), arrow.id)
        XCTAssertNil(AnnotationGeometry.hitTest([arrow], at: CGPoint(x: 0.5, y: 0.2), tolerance: 0.01))
        XCTAssertNil(AnnotationGeometry.hitTest([arrow], at: CGPoint(x: 0.95, y: 0.1), tolerance: 0.01))
    }
}
