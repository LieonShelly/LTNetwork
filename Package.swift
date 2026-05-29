//
//  Created by lieon on 2026/05/17.
//  This code is protected by intellectual property rights.
//

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
