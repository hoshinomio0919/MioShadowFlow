// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MioShadowFlow",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MioShadowFlow", targets: ["MioShadowFlow"])
    ],
    targets: [
        .target(name: "MioShadowFlow"),
        .testTarget(name: "MioShadowFlowTests", dependencies: ["MioShadowFlow"])
    ]
)
