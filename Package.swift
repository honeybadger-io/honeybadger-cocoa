// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "Honeybadger",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "Honeybadger",
            targets: ["Honeybadger", "HoneybadgerSwift"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Honeybadger",
            path: "Sources/ObjC",
            cSettings: [
                .headerSearchPath("Sources/ObjC/include")
            ]
        ),
        .target(
            name: "HoneybadgerSwift",
            dependencies: ["Honeybadger"],
            path: "Sources/Swift"
        ),
        .executableTarget(
            name: "HoneybadgerTests",
            dependencies: ["Honeybadger"],
            path: "Tests/HoneybadgerTests"
        )
    ]
)
