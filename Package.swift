// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MediaLatch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MediaLatch", targets: ["MediaLatch"])
    ],
    targets: [
        .executableTarget(
            name: "MediaLatch",
            path: "Sources/MediaLatch"
        ),
        .testTarget(
            name: "MediaLatchTests",
            dependencies: ["MediaLatch"],
            path: "Tests/MediaLatchTests"
        )
    ]
)
