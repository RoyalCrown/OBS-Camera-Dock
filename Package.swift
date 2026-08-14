// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OBSCameraDock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CameraDockHelper", targets: ["CameraDockHelper"])
    ],
    targets: [
        .target(
            name: "UVCHeaders",
            path: "Sources/UVCHeaders",
            publicHeadersPath: "include"
        ),
        .target(
            name: "UVCControls",
            dependencies: ["UVCHeaders"],
            path: "Sources/UVCControls",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CameraDockHelper",
            dependencies: ["UVCControls"],
            path: "Sources/CameraDockHelper",
            resources: [.copy("Resources/index.html")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
