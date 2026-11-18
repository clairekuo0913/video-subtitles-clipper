import XCTest
@testable import StitchCore

final class ImageLoadingTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLoadSortsNaturallyAndIgnoresNonImages() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var urls: [URL] = []
        for n in ["shot 2.png", "shot 10.png", "shot 1.png"] {
            let url = dir.appendingPathComponent(n)
            try PNGOutput.encode(solidImage(width: 40, height: 30))!.write(to: url)
            urls.append(url)
        }
        let txt = dir.appendingPathComponent("note.txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        urls.append(txt)

        let loaded = ImageLoading.load(urls: urls)
        XCTAssertEqual(loaded.map(\.name), ["shot 1.png", "shot 2.png", "shot 10.png"])
        XCTAssertEqual(loaded[0].image.width, 40)
    }

    func testThumbnailIsDownsampledAndKeepsAspect() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("big.png")
        try PNGOutput.encode(solidImage(width: 6000, height: 3000))!.write(to: url)
        let item = try XCTUnwrap(ImageLoading.load(url: url))
        XCTAssertEqual(item.image.width, 6000)
        XCTAssertEqual(item.thumbnail.width, ImageLoading.thumbnailMaxPixel)
        XCTAssertEqual(item.thumbnail.height, ImageLoading.thumbnailMaxPixel / 2)
    }
}
