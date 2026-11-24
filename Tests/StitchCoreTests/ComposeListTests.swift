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

    // MARK: per-scene band

    private let bA = CropBand(top: 0.5, bottom: 0.8)
    private let bB = CropBand(top: 0.2, bottom: 0.4)

    func testBandDefaultsToNil() {
        XCTAssertTrue(list(3).items.allSatisfy { $0.band == nil })
    }

    func testSetBandOnFrameStoresOverride() {
        var l = list(3)
        XCTAssertNil(err(l.setBand(bA, forFrame: l.items[0].id)))
        XCTAssertEqual(l.items[0].band, bA)
    }

    func testSetBandRejectsSubtitleAndUnknownId() {
        var l = list(3)
        XCTAssertEqual(err(l.setBand(bA, forFrame: l.items[1].id)), .itemNotFound)
        XCTAssertNil(l.items[1].band)
        XCTAssertEqual(err(l.setBand(bA, forFrame: UUID())), .itemNotFound)
    }

    /// 三幕：f0 s1 | f2 s3 | f4
    private func threeScenes() -> ComposeList {
        var l = list(5)
        _ = l.setKind(id: l.items[2].id, to: .frame)
        _ = l.setKind(id: l.items[4].id, to: .frame)
        return l
    }

    func testEffectiveBandsAllDefaultWhenNoOverride() {
        let l = threeScenes()
        let eb = l.effectiveBands(default: bA)
        XCTAssertEqual(eb.count, 5)
        XCTAssertTrue(eb.values.allSatisfy { $0 == bA })
    }

    func testSecondSceneOverrideDoesNotAffectFirst() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        let eb = l.effectiveBands(default: bA)
        XCTAssertEqual(eb[l.items[0].id], bA)
        XCTAssertEqual(eb[l.items[1].id], bA)
        XCTAssertEqual(eb[l.items[2].id], bB)
        XCTAssertEqual(eb[l.items[3].id], bB)
    }

    func testThirdSceneFollowsSecond() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        XCTAssertEqual(l.effectiveBands(default: bA)[l.items[4].id], bB)
    }

    func testFirstSceneChangeFollowedByUncustomizedButNotCustomized() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        let newDefault = CropBand(top: 0.6, bottom: 0.9)
        let eb = l.effectiveBands(default: newDefault)
        XCTAssertEqual(eb[l.items[0].id], newDefault)
        XCTAssertEqual(eb[l.items[2].id], bB)
        XCTAssertEqual(eb[l.items[4].id], bB)
        // 未自訂第二幕時，後面也跟隨新預設
        let l2 = threeScenes()
        XCTAssertTrue(l2.effectiveBands(default: newDefault).values.allSatisfy { $0 == newDefault })
    }

    func testFirstFrameOverrideTakesPrecedenceOverDefault() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[0].id)
        let eb = l.effectiveBands(default: bA)
        XCTAssertEqual(eb[l.items[1].id], bB)
        XCTAssertEqual(eb[l.items[2].id], bB)
    }

    func testSetKindToSubtitleClearsBand() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        _ = l.setKind(id: l.items[2].id, to: .subtitle)
        XCTAssertNil(l.items[2].band)
        XCTAssertEqual(l.effectiveBands(default: bA)[l.items[2].id], bA)
    }

    func testToggleKindClearsBandBothWays() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        _ = l.toggleKind(id: l.items[2].id) // frame -> subtitle
        XCTAssertNil(l.items[2].band)
        _ = l.toggleKind(id: l.items[2].id) // subtitle -> frame
        XCTAssertEqual(l.items[2].kind, .frame)
        XCTAssertNil(l.items[2].band)
    }

    func testSetKindToFrameHasNilBand() {
        var l = list(3)
        _ = l.setKind(id: l.items[1].id, to: .frame)
        XCTAssertNil(l.items[1].band)
    }

    func testRemoveFirstClearsNewFirstFramesBand() {
        var l = list(3)
        // 新首項原為 subtitle；人為設定殘留 band 也必須被清除
        _ = l.setKind(id: l.items[1].id, to: .frame)
        _ = l.setBand(bB, forFrame: l.items[1].id)
        _ = l.setKind(id: l.items[1].id, to: .subtitle)
        _ = l.remove(id: l.items[0].id)
        XCTAssertEqual(l.items[0].kind, .frame)
        XCTAssertNil(l.items[0].band)
    }

    func testRemoveFirstWhenNextIsCustomFrameKeepsItsBand() {
        var l = list(3)
        _ = l.setKind(id: l.items[1].id, to: .frame)
        _ = l.setBand(bB, forFrame: l.items[1].id)
        _ = l.remove(id: l.items[0].id)
        XCTAssertEqual(l.items[0].band, bB)
    }

    func testMovePreservesOverride() {
        var l = threeScenes()
        let id = l.items[2].id
        _ = l.setBand(bB, forFrame: id)
        XCTAssertNil(err(l.move(from: 2, to: 3)))
        XCTAssertEqual(l.items.first(where: { $0.id == id })?.band, bB)
    }

    func testMoveSubtitleAcrossScenesUsesTargetSceneBand() {
        var l = threeScenes()
        _ = l.setBand(bB, forFrame: l.items[2].id)
        let sub = l.items[1].id // 第一幕字幕
        XCTAssertNil(err(l.move(from: 1, to: 2))) // 移到第二幕 frame 之後
        XCTAssertEqual(l.effectiveBands(default: bA)[sub], bB)
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
