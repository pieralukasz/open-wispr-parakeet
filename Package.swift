// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "open-wispr",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "300165b240c45375add402265f62410b6df33cf1"
        )
    ],
    targets: [
        .target(
            name: "OpenWisprLib",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/OpenWisprLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "open-wispr",
            dependencies: ["OpenWisprLib"],
            path: "Sources/OpenWispr"
        ),
        .testTarget(
            name: "OpenWisprTests",
            dependencies: ["OpenWisprLib"],
            path: "Tests/OpenWisprTests"
        ),
    ]
)
