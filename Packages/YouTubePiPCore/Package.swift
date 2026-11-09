// swift-tools-version: 5.9
import PackageDescription

/// Logica pura do app (sem UIKit/WebKit/AVFoundation), testavel no Mac com `swift test`.
let package = Package(
    name: "YouTubePiPCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "YouTubePiPCore", targets: ["YouTubePiPCore"])
    ],
    targets: [
        .target(
            name: "YouTubePiPCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "YouTubePiPCoreTests",
            dependencies: ["YouTubePiPCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
