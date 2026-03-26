// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LTNetwork",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "LTNetwork", targets: ["LTNetwork"]),
    ],
    targets: [
        .target(
            name: "LTNetwork",
            path: "Source"
        ),
        .testTarget(
            name: "LTNetworkTests",
            dependencies: ["LTNetwork"],
            path: "Tests"
        ),
    ]
)
