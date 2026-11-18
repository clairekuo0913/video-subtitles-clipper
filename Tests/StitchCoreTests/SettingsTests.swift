import XCTest
@testable import StitchCore

final class SettingsTests: XCTestCase {
    private func store() -> SettingsStore {
        let name = "SettingsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return SettingsStore(defaults: d)
    }

    func testDefaultsWhenEmpty() {
        let s = store()
        XCTAssertEqual(s.band, CropBand.default)
        XCTAssertEqual(s.outputScale, .percent100)
    }

    func testBandRoundTrip() {
        let s = store()
        s.band = CropBand(top: 0.6, bottom: 0.9)
        XCTAssertEqual(s.band, CropBand(top: 0.6, bottom: 0.9))
    }

    func testOutputScaleRoundTripAndInvalid() {
        let s = store()
        s.outputScale = .percent50
        XCTAssertEqual(s.outputScale, .percent50)
    }

    func testZoomClampAndSteps() {
        XCTAssertEqual(ViewZoom.clamp(0.01), 0.25)
        XCTAssertEqual(ViewZoom.clamp(99), 4.0)
        XCTAssertEqual(ViewZoom.clamp(.nan), 1.0)
        XCTAssertEqual(ViewZoom.zoomedIn(4.0), 4.0)
        XCTAssertEqual(ViewZoom.zoomedOut(0.25), 0.25)
        XCTAssertEqual(ViewZoom.zoomedIn(1.0), 1.25, accuracy: 1e-9)
        XCTAssertEqual(ViewZoom.zoomedOut(1.25), 1.0, accuracy: 1e-9)
    }
}
