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
        // Tools version 6.0 builds every target in Swift 6 language mode.
        // Pure logic: physics, models, settings, geometry, sound synthesis.
        // Imports Foundation and CoreGraphics only, so it is fully unit-testable.
        .target(
            name: "HangingCharmsCore"
        ),
        // The macOS head: overlay panel, menu bar, Customize window, services.
        .executableTarget(
            name: "HangingCharms",
            dependencies: ["HangingCharmsCore"]
        ),
        .testTarget(
            name: "HangingCharmsCoreTests",
            dependencies: ["HangingCharmsCore"]
        ),
    ]
)
