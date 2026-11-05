// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 3.3): Flutter 3.47.9 plugin template layout.

import PackageDescription

let package = Package(
    name: "pencil_bridge",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "pencil-bridge", targets: ["pencil_bridge"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "pencil_bridge",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
