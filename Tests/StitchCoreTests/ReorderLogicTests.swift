import XCTest
@testable import StitchCore

final class ReorderLogicTests: XCTestCase {
    // MARK: 游標 y → 插入索引

    func testInsertionIndexUpperAndLowerHalf() {
        let h = [100.0, 100.0, 100.0]
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 10, rowHeights: h), 0)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 49, rowHeights: h), 0)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 51, rowHeights: h), 1)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 149, rowHeights: h), 1)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 151, rowHeights: h), 2)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 299, rowHeights: h), 3)
    }

    func testInsertionIndexVariableHeights() {
        let h = [40.0, 200.0, 60.0] // 邊界 0,40,240,300；中線 20,140,270
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 130, rowHeights: h), 1)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 150, rowHeights: h), 2)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 280, rowHeights: h), 3)
    }

    func testInsertionIndexClamps() {
        let h = [100.0, 100.0]
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: -500, rowHeights: h), 0)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 9999, rowHeights: h), 2)
        XCTAssertEqual(ReorderLogic.insertionIndex(forY: 5, rowHeights: []), 0)
    }

    // MARK: 合法性與最終索引

    private func kinds(_ s: String) -> [ItemKind] { s.map { $0 == "F" ? .frame : .subtitle } }

    func testFinalIndexForwardAndBackward() {
        let k = kinds("FSSS")
        // 把索引 1 插到索引 4（最後）→ 移動後最終索引 3
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 4, from: 1, kinds: k), .init(isValid: true, to: 3))
        // 把索引 3 插到 1 之前 → 最終索引 1
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 1, from: 3, kinds: k), .init(isValid: true, to: 1))
    }

    func testDropAdjacentToSelfIsNoOp() {
        let k = kinds("FSS")
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 1, from: 1, kinds: k), .init(isValid: true, to: 1))
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 2, from: 1, kinds: k), .init(isValid: true, to: 1))
    }

    func testSubtitleToFrontIsInvalid() {
        XCTAssertFalse(ReorderLogic.resolveDrop(insertion: 0, from: 2, kinds: kinds("FSS")).isValid)
    }

    func testFrameToFrontIsValid() {
        // S 在前不可能，但 F 在中間移到最前合法
        let k: [ItemKind] = [.frame, .subtitle, .frame]
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 0, from: 2, kinds: k), .init(isValid: true, to: 0))
    }

    func testMovingFirstFrameBehindSubtitleIsInvalid() {
        XCTAssertFalse(ReorderLogic.resolveDrop(insertion: 2, from: 0, kinds: kinds("FSS")).isValid)
    }

    func testCrossSceneMoveIsValid() {
        // 第一幕 F S，第二幕 F S：把第一幕的字幕(1)移到第二幕畫面之後(插入索引 3)
        XCTAssertEqual(ReorderLogic.resolveDrop(insertion: 3, from: 1, kinds: kinds("FSFS")), .init(isValid: true, to: 2))
    }

    func testResolveDropMatchesComposeList() {
        let ks: [[ItemKind]] = [kinds("FSSS"), kinds("FSFS"), [.frame, .frame, .subtitle]]
        for k in ks {
            for from in k.indices {
                for ins in 0...k.count {
                    var l = ComposeList()
                    for i in k.indices { l.append(image: solidImage(width: 2, height: 2), name: "n\(i)") }
                    for i in k.indices { _ = l.setKind(id: l.items[i].id, to: k[i]) }
                    let r = ReorderLogic.resolveDrop(insertion: ins, from: from, kinds: k)
                    let result = l.move(from: from, to: ins > from ? ins - 1 : ins)
                    var failure: ComposeError?
                    if case .failure(let e) = result { failure = e }
                    XCTAssertEqual(r.isValid, failure == nil, "\(k) \(from)→\(ins)")
                    if r.isValid { XCTAssertEqual(r.to, ins > from ? ins - 1 : ins) }
                }
            }
        }
    }

    // MARK: 邊緣捲動速度

    func testEdgeSpeedZeroInMiddle() {
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 300, viewportHeight: 600), 0)
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 60, viewportHeight: 600), 0)
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 540, viewportHeight: 600), 0)
    }

    func testEdgeSpeedSignAndMonotonic() {
        let top = [50.0, 40, 30, 20, 10, 0].map { ReorderLogic.edgeScrollSpeed(cursorY: $0, viewportHeight: 600) }
        XCTAssertTrue(top.allSatisfy { $0 < 0 })
        for i in 1..<top.count { XCTAssertLessThan(top[i], top[i - 1]) } // 越近越快（更負）
        let bottom = [550.0, 560, 570, 580, 590, 600].map { ReorderLogic.edgeScrollSpeed(cursorY: $0, viewportHeight: 600) }
        XCTAssertTrue(bottom.allSatisfy { $0 > 0 })
        for i in 1..<bottom.count { XCTAssertGreaterThan(bottom[i], bottom[i - 1]) }
    }

    func testEdgeSpeedCappedAndSymmetric() {
        let max = ReorderLogic.maxScrollSpeed
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 600, viewportHeight: 600), max, accuracy: 0.001)
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 0, viewportHeight: 600), -max, accuracy: 0.001)
        // 游標拖出可視區外仍夾限
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 900, viewportHeight: 600), max, accuracy: 0.001)
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: -300, viewportHeight: 600), -max, accuracy: 0.001)
    }

    func testEdgeSpeedTinyViewportDoesNotOverlapZones() {
        // 可視區比兩個邊緣區還小：中點必為 0
        XCTAssertEqual(ReorderLogic.edgeScrollSpeed(cursorY: 50, viewportHeight: 100), 0, accuracy: 0.001)
    }
}
