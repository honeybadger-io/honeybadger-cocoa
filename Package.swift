// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "Honeybadger",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
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
        )
    ]
)
