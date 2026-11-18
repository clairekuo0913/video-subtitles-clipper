import XCTest
import CoreGraphics
@testable import StitchCore

final class AnnotationModelTests: XCTestCase {
    private let H: CGFloat = 3.0 // canvasHeightRatio

    private func rectAnn(_ r: CGRect) -> Annotation {
        Annotation(shape: .rectangle(rect: r, style: .default))
    }
    private func arrowAnn(_ a: CGPoint, _ b: CGPoint) -> Annotation {
        Annotation(shape: .arrow(start: a, end: b, style: .default))
    }

    // MARK: 1.1 model & list

    func testKinds() {
        XCTAssertEqual(rectAnn(.zero).kind, .rectangle)
        XCTAssertEqual(arrowAnn(.zero, .zero).kind, .arrow)
        XCTAssertEqual(Annotation(shape: .mosaic(rect: .zero)).kind, .mosaic)
        XCTAssertEqual(Annotation(shape: .text(rect: .zero, text: "a", style: .default)).kind, .text)
    }

    func testAddPutsNewOnTopAndLookup() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        let b = l.add(rectAnn(CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        XCTAssertEqual(l.annotations.map(\.id), [a.id, b.id]) // 最後者在最上
        XCTAssertEqual(l.annotation(id: b.id)?.id, b.id)
        XCTAssertNil(l.annotation(id: UUID()))
    }

    func testUpdateAndRemove() {
        var l = AnnotationList()
        let a = l.add(Annotation(shape: .text(rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1), text: "hi", style: .default)), canvasHeightRatio: H)
        XCTAssertTrue(l.update(id: a.id) { ann in
            if case let .text(r, _, s) = ann.shape { ann.shape = .text(rect: r, text: "yo", style: s) }
        })
        if case let .text(_, t, _)? = l.annotation(id: a.id)?.shape { XCTAssertEqual(t, "yo") } else { XCTFail() }
        XCTAssertFalse(l.update(id: UUID()) { _ in })
        XCTAssertTrue(l.remove(id: a.id))
        XCTAssertTrue(l.annotations.isEmpty)
        XCTAssertFalse(l.remove(id: a.id))
    }

    func testZOrderStableAfterUpdate() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        let b = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.move(id: a.id, dx: 0.1, dy: 0, canvasHeightRatio: H)
        XCTAssertEqual(l.annotations.map(\.id), [a.id, b.id])
    }

    // MARK: 1.2 clamping

    func testAddClampsRectIntoCanvas() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.8, y: 2.9, width: 0.5, height: 0.5)), canvasHeightRatio: H)
        guard case let .rectangle(r, _) = a.shape else { return XCTFail() }
        XCTAssertEqual(r.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(r.maxY, H, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(r.minX, 0)
    }

    func testAddNormalizesNegativeSizeFromReverseDrag() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.5, y: 0.5, width: -0.2, height: -0.1)), canvasHeightRatio: H)
        guard case let .rectangle(r, _) = a.shape else { return XCTFail() }
        XCTAssertEqual(r.minX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.2, accuracy: 1e-9)
    }

    func testMinimumSize() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.5, y: 0.5, width: 0, height: 0)), canvasHeightRatio: H)
        guard case let .rectangle(r, _) = a.shape else { return XCTFail() }
        XCTAssertEqual(r.width, AnnotationLimits.minSize, accuracy: 1e-9)
        XCTAssertEqual(r.height, AnnotationLimits.minSize, accuracy: 1e-9)
    }

    func testMoveKeepsSizeAndStaysInside() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.5, y: 1, width: 0.3, height: 0.2)), canvasHeightRatio: H)
        l.move(id: a.id, dx: 5, dy: -9, canvasHeightRatio: H)
        guard case let .rectangle(r, _)? = l.annotation(id: a.id)?.shape else { return XCTFail() }
        XCTAssertEqual(r.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.2, accuracy: 1e-9)
    }

    func testResizeClamps() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.resize(id: a.id, to: CGRect(x: -1, y: -1, width: 9, height: 99), canvasHeightRatio: H)
        guard case let .rectangle(r, _)? = l.annotation(id: a.id)?.shape else { return XCTFail() }
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1, height: H))
    }

    func testArrowEndpointsClamped() {
        var l = AnnotationList()
        let a = l.add(arrowAnn(CGPoint(x: -0.5, y: 0.2), CGPoint(x: 1.5, y: 9)), canvasHeightRatio: H)
        guard case let .arrow(s, e, _) = a.shape else { return XCTFail() }
        XCTAssertEqual(s, CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(e, CGPoint(x: 1, y: H))
    }

    func testArrowMoveKeepsVectorAndBoundsInside() {
        var l = AnnotationList()
        let a = l.add(arrowAnn(CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.6, y: 0.5)), canvasHeightRatio: H)
        l.move(id: a.id, dx: 10, dy: 10, canvasHeightRatio: H)
        guard case let .arrow(s, e, _)? = l.annotation(id: a.id)?.shape else { return XCTFail() }
        XCTAssertEqual(e.x, 1, accuracy: 1e-9)
        XCTAssertEqual(e.y, H, accuracy: 1e-9)
        XCTAssertEqual(e.x - s.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(e.y - s.y, 0.3, accuracy: 1e-9)
    }

    func testArrowResizeEndpointsClampedAndMinLength() {
        var l = AnnotationList()
        let a = l.add(arrowAnn(CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.6, y: 0.5)), canvasHeightRatio: H)
        l.resize(id: a.id, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5), canvasHeightRatio: H)
        guard case let .arrow(s, e, _)? = l.annotation(id: a.id)?.shape else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(hypot(e.x - s.x, e.y - s.y), AnnotationLimits.minSize - 1e-9)
    }

    // MARK: 1.3 undo

    func testUndoAdd() {
        var l = AnnotationList()
        l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        XCTAssertTrue(l.undo())
        XCTAssertTrue(l.annotations.isEmpty)
    }

    func testUndoMoveResizeRestyleRemove() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        let original = l.annotations
        l.move(id: a.id, dx: 0.3, dy: 0.3, canvasHeightRatio: H)
        XCTAssertNotEqual(l.annotations, original)
        XCTAssertTrue(l.undo()); XCTAssertEqual(l.annotations, original)

        l.resize(id: a.id, to: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), canvasHeightRatio: H)
        XCTAssertTrue(l.undo()); XCTAssertEqual(l.annotations, original)

        l.update(id: a.id) { $0.shape = .rectangle(rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                                                   style: LineStyle(color: .blue, width: 0.01)) }
        XCTAssertNotEqual(l.annotations, original)
        XCTAssertTrue(l.undo()); XCTAssertEqual(l.annotations, original)

        l.remove(id: a.id)
        XCTAssertTrue(l.annotations.isEmpty)
        XCTAssertTrue(l.undo()); XCTAssertEqual(l.annotations, original) // 還原且位置（z 順序）不變
    }

    func testUndoRestoresZOrderOfRemoved() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.add(rectAnn(CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.remove(id: a.id)
        l.undo()
        XCTAssertEqual(l.annotations.first?.id, a.id)
    }

    func testUndoWhenNothingHasNoEffect() {
        var l = AnnotationList()
        XCTAssertFalse(l.undo())
        XCTAssertTrue(l.annotations.isEmpty)
        l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        XCTAssertTrue(l.undo())
        XCTAssertFalse(l.undo())
    }

    func testMultipleUndoOrder() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.add(rectAnn(CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.undo()
        XCTAssertEqual(l.annotations.map(\.id), [a.id])
    }

    func testGestureCoalescesIntoOneUndo() {
        var l = AnnotationList()
        let a = l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        let original = l.annotations
        l.checkpoint()
        for _ in 0..<5 { l.move(id: a.id, dx: 0.05, dy: 0, canvasHeightRatio: H, recordUndo: false) }
        XCTAssertNotEqual(l.annotations, original)
        XCTAssertTrue(l.undo())
        XCTAssertEqual(l.annotations, original)
    }

    func testClearRemovesAnnotationsAndUndoHistory() {
        var l = AnnotationList()
        l.add(rectAnn(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), canvasHeightRatio: H)
        l.clear()
        XCTAssertTrue(l.annotations.isEmpty)
        XCTAssertFalse(l.canUndo)
        XCTAssertFalse(l.undo())
        XCTAssertTrue(l.annotations.isEmpty)
    }
}
