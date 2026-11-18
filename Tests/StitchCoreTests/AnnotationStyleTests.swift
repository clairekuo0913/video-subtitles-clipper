import XCTest
@testable import StitchCore

final class AnnotationStyleTests: XCTestCase {
    private func store() -> AnnotationStyleStore {
        let name = "AnnotationStyleTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return AnnotationStyleStore(defaults: d)
    }

    func testDefaultsWhenEmpty() {
        let s = store()
        XCTAssertEqual(s.textStyle, .default)
        XCTAssertEqual(s.rectangleStyle, .default)
        XCTAssertEqual(s.arrowStyle, .default)
        XCTAssertNil(TextStyle.default.fillColor)      // 預設無底色
        XCTAssertNil(TextStyle.default.border)         // 預設無邊框
        XCTAssertGreaterThan(TextStyle.default.fontSize, 0)
        XCTAssertGreaterThan(LineStyle.default.width, 0)
    }

    func testTextStyleRoundTripIncludingNoFill() {
        let s = store()
        let custom = TextStyle(textColor: .red, fillColor: .yellow, fontSize: 0.05, bold: true,
                               border: BorderStyle(color: .blue, width: 0.004))
        s.textStyle = custom
        XCTAssertEqual(s.textStyle, custom)
        var noFill = custom; noFill.fillColor = nil; noFill.border = nil
        s.textStyle = noFill
        XCTAssertEqual(s.textStyle, noFill)
        XCTAssertNil(s.textStyle.fillColor)
    }

    func testRectangleAndArrowSeparate() {
        let s = store()
        s.arrowStyle = LineStyle(color: .red, width: 0.01)
        XCTAssertEqual(s.arrowStyle, LineStyle(color: .red, width: 0.01))
        XCTAssertEqual(s.rectangleStyle, .default)
        s.rectangleStyle = LineStyle(color: .blue, width: 0.02)
        XCTAssertEqual(s.rectangleStyle.color, .blue)
        XCTAssertEqual(s.arrowStyle.color, .red)
    }

    func testCorruptedDataFallsBackToDefault() {
        let name = "AnnotationStyleTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.set(Data([1, 2, 3]), forKey: AnnotationStyleStore.arrowKey)
        XCTAssertEqual(AnnotationStyleStore(defaults: d).arrowStyle, .default)
    }

    func testColorCodable() throws {
        let c = RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        let back = try JSONDecoder().decode(RGBAColor.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}
