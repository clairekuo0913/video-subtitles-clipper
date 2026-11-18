import XCTest
import CoreGraphics
@testable import StitchCore

final class AnnotationClipboardTests: XCTestCase {
    private let H: CGFloat = 3
    private let img = solidImage(width: 20, height: 10)
    private let step: CGFloat = 0.02

    private var samples: [Annotation] {
        [
            Annotation(shape: .text(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1), text: "hi", style: .default)),
            Annotation(shape: .rectangle(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1), style: .default)),
            Annotation(shape: .arrow(start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.4, y: 0.3), style: .default)),
            Annotation(shape: .mosaic(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))),
            Annotation(shape: .image(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15), image: img)),
        ]
    }

    private func moved(_ a: Annotation, by d: CGFloat) -> Annotation {
        a.moved(dx: d, dy: d, canvasHeightRatio: H)
    }

    func testEmptyReturnsNil() {
        var c = AnnotationClipboard()
        XCTAssertNil(c.pasted(canvasHeightRatio: H))
        XCTAssertFalse(c.hasContent)
    }

    func testPasteHasNewIdSameContentOffset() {
        for original in samples {
            var c = AnnotationClipboard()
            c.copy(original)
            let p = c.pasted(canvasHeightRatio: H)!
            XCTAssertNotEqual(p.id, original.id)
            var expected = moved(original, by: step)
            expected = Annotation(id: p.id, shape: expected.shape)
            XCTAssertEqual(p, expected, "\(original.kind)")
            XCTAssertEqual(p.kind, original.kind)
        }
    }

    func testImageSharesCGImageReference() {
        var c = AnnotationClipboard()
        c.copy(samples[4])
        guard case let .image(_, i) = c.pasted(canvasHeightRatio: H)!.shape else { return XCTFail() }
        XCTAssertTrue(i === img)
    }

    func testConsecutivePastesAccumulateOffset() {
        for original in samples {
            var c = AnnotationClipboard()
            c.copy(original)
            let p1 = c.pasted(canvasHeightRatio: H)!
            let p2 = c.pasted(canvasHeightRatio: H)!
            XCTAssertEqual(p2.bounds.minX - p1.bounds.minX, step, accuracy: 1e-9)
            XCTAssertEqual(p2.bounds.minY - p1.bounds.minY, step, accuracy: 1e-9)
            XCTAssertNotEqual(p1.id, p2.id)
            XCTAssertEqual(p1.bounds.minX - original.bounds.minX, step, accuracy: 1e-9)
        }
    }

    func testClampedNearBottomRightBoundary() {
        let r = Annotation(shape: .rectangle(rect: CGRect(x: 0.7, y: H - 0.1, width: 0.3, height: 0.1), style: .default))
        var c = AnnotationClipboard()
        c.copy(r)
        let p = c.pasted(canvasHeightRatio: H)!
        XCTAssertLessThanOrEqual(p.bounds.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(p.bounds.maxY, H + 1e-9)
        XCTAssertEqual(p.bounds.size, r.bounds.size)

        let img = Annotation(shape: .image(rect: CGRect(x: 0.7, y: H - 0.15, width: 0.3, height: 0.15), image: self.img))
        c.copy(img)
        let pi = c.pasted(canvasHeightRatio: H)!
        XCTAssertLessThanOrEqual(pi.bounds.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(pi.bounds.maxY, H + 1e-9)
    }

    func testArrowClampedKeepsBothEndpointsInside() {
        let a = Annotation(shape: .arrow(start: CGPoint(x: 0.6, y: H - 0.3), end: CGPoint(x: 1, y: H), style: .default))
        var c = AnnotationClipboard()
        c.copy(a)
        guard case let .arrow(s, e, _) = c.pasted(canvasHeightRatio: H)!.shape else { return XCTFail() }
        for p in [s, e] {
            XCTAssertTrue(p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= H)
        }
        XCTAssertEqual(e.x - s.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(e.y - s.y, 0.3, accuracy: 1e-9)
    }

    func testCopyReplacesContentAndResetsCount() {
        var c = AnnotationClipboard()
        c.copy(samples[0])
        _ = c.pasted(canvasHeightRatio: H)
        _ = c.pasted(canvasHeightRatio: H)
        let other = samples[1]
        c.copy(other)
        let p = c.pasted(canvasHeightRatio: H)!
        XCTAssertEqual(p.kind, .rectangle)
        XCTAssertEqual(p.bounds.minX - other.bounds.minX, step, accuracy: 1e-9)
    }

    func testClearRemovesContent() {
        var c = AnnotationClipboard()
        c.copy(samples[0])
        c.clear()
        XCTAssertNil(c.pasted(canvasHeightRatio: H))
    }
}
