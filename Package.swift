// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Honeybadger",
    platforms: [.iOS(.v13)],
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
