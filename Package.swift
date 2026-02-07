// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ImageStreamer",
    platforms: [
        .iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ImageStreamer",
            targets: ["ImageStreamer"]
        ),
    ],
    targets: [
        .target(
            name: "ImageStreamer"
        ),
        .testTarget(
            name: "ImageStreamerTests",
            dependencies: ["ImageStreamer"]
        ),
    ]
)
