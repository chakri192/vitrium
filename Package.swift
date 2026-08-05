// swift-tools-version:6.0
import PackageDescription

// The app is split into a library plus two thin executables so the test runner
// can `@testable import` the real code. `swift test` is deliberately not used:
// XCTest ships only with Xcode, and the Command Line Tools' swift-testing is
// missing its Foundation overlay — so the runner is an ordinary executable that
// depends on nothing but the standard library and AppKit.
let package = Package(
    name: "Vitrium",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VitriumKit",
            path: "Sources/VitriumKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Vitrium",
            dependencies: ["VitriumKit"],
            path: "Sources/Vitrium",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VitriumTests",
            dependencies: ["VitriumKit"],
            path: "Sources/VitriumTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
