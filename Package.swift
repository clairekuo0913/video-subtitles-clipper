// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SubtitleClipper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StitchCore"),
        .executableTarget(name: "SubtitleClipper", dependencies: ["StitchCore"]),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"]),
    ]
)
