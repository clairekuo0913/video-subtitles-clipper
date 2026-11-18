import XCTest
@testable import StitchCore

final class ComposeListTests: XCTestCase {
    private func err(_ r: Result<Void, ComposeError>) -> ComposeError? {
        if case .failure(let e) = r { return e }
        return nil
    }
    private func list(_ n: Int) -> ComposeList {
        var l = ComposeList()
        for i in 0..<n { l.append(image: solidImage(width: 10, height: 10), name: "n\(i)") }
        return l
    }
    private func names(_ l: ComposeList) -> [String] { l.items.map(\.name) }

    func testDefaultKindsFourImagesFormOneScene() {
        let l = list(4)
        XCTAssertEqual(l.items.map(\.kind), [.frame, .subtitle, .subtitle, .subtitle])
        XCTAssertEqual(l.scenes.count, 1)
        XCTAssertEqual(l.scenes[0].count, 4)
    }

    func testAppendToNonEmptyIsSubtitle() {
        var l = list(1)
        XCTAssertEqual(l.append(image: solidImage(width: 1, height: 1), name: "x").kind, .subtitle)
    }

    func testToggleThirdToFrameStartsSecondScene() {
        var l = list(4)
        XCTAssertNil(err(l.toggleKind(id: l.items[2].id)))
        XCTAssertEqual(l.scenes.map { $0.map(\.name) }, [["n0", "n1"], ["n2", "n3"]])
    }

    func testRejectSwitchingFirstToSubtitle() {
        var l = list(3)
        XCTAssertEqual(err(l.setKind(id: l.items[0].id, to: .subtitle)), .firstItemMustBeFrame)
        XCTAssertEqual(l.items[0].kind, .frame)
        XCTAssertEqual(err(l.toggleKind(id: l.items[0].id)), .firstItemMustBeFrame)
    }

    func testRejectMovingSubtitleToFront() {
        var l = list(3)
        let before = names(l)
        XCTAssertEqual(err(l.move(from: 2, to: 0)), .firstItemMustBeFrame)
        XCTAssertEqual(names(l), before)
    }

    func testMovingFrameDownWhenFirstWouldBecomeSubtitleRejected() {
        var l = list(3)
        XCTAssertEqual(err(l.move(from: 0, to: 2)), .firstItemMustBeFrame)
        XCTAssertEqual(names(l), ["n0", "n1", "n2"])
    }

    func testRemoveFirstPromotesNextToFrame() {
        var l = list(3)
        XCTAssertNil(err(l.remove(id: l.items[0].id)))
        XCTAssertEqual(names(l), ["n1", "n2"])
        XCTAssertEqual(l.items[0].kind, .frame)
    }

    func testRemoveMiddleAndUnknown() {
        var l = list(3)
        XCTAssertNil(err(l.remove(id: l.items[1].id)))
        XCTAssertEqual(names(l), ["n0", "n2"])
        XCTAssertEqual(err(l.remove(id: UUID())), .itemNotFound)
    }

    func testClear() {
        var l = list(3)
        l.clear()
        XCTAssertTrue(l.items.isEmpty)
        XCTAssertTrue(l.scenes.isEmpty)
    }

    func testReorderWithinScene() {
        var l = list(4)
        XCTAssertNil(err(l.move(from: 1, to: 3)))
        XCTAssertEqual(names(l), ["n0", "n2", "n3", "n1"])
    }

    func testMoveAcrossScenes() {
        var l = list(5) // f s s s s
        _ = l.setKind(id: l.items[3].id, to: .frame) // scenes: [n0 n1 n2] [n3 n4]
        XCTAssertNil(err(l.move(from: 1, to: 3))) // n1 after n3
        XCTAssertEqual(l.scenes.map { $0.map(\.name) }, [["n0", "n2"], ["n3", "n1", "n4"]])
    }

    func testMoveOutOfRange() {
        var l = list(2)
        XCTAssertEqual(err(l.move(from: 0, to: 5)), .indexOutOfRange)
    }

    func testNaturalSort() {
        XCTAssertEqual(naturalSorted(["shot 2.png", "shot 10.png", "shot 1.png"]),
                       ["shot 1.png", "shot 2.png", "shot 10.png"])
        let sorted = naturalSorted([("shot 10", 1), ("shot 1", 2)], by: { $0.0 })
        XCTAssertEqual(sorted.map(\.1), [2, 1])
    }
}
