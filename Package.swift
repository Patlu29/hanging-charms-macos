// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HangingCharms",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HangingCharms", targets: ["HangingCharms"]),
        .library(name: "HangingCharmsCore", targets: ["HangingCharmsCore"]),
    ],
    targets: [
        // Pure logic: physics, models, settings, geometry, sound synthesis.
        // Imports Foundation and CoreGraphics only, so it is fully unit-testable.
        .target(
            name: "HangingCharmsCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The macOS head: overlay panel, menu bar, Customize window, services.
        .executableTarget(
            name: "HangingCharms",
            dependencies: ["HangingCharmsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HangingCharmsCoreTests",
            dependencies: ["HangingCharmsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
