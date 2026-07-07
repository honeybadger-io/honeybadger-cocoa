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
            path: "Tests/HoneybadgerTests",
            cSettings: [
                .define("HB_TEST_BUILD", to: "1"),
                .headerSearchPath("../../Sources/ObjC/include"),
                .headerSearchPath("../../Sources/ObjC")
            ]
        ),
        .executableTarget(
            name: "HoneybadgerProductionSmoke",
            dependencies: ["Honeybadger"],
            path: "Examples/ProductionSmokeTest",
            exclude: ["README.md", "run_signal_smoke.sh"]
        )
    ]
)
