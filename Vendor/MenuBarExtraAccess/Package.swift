// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarExtraAccess",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "MenuBarExtraAccess", targets: ["MenuBarExtraAccess"])
    ],
    targets: [
        .target(name: "MenuBarExtraAccess")
    ]
)
