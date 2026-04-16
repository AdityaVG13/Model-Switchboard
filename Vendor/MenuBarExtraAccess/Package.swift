// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MenuBarExtraAccess",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "MenuBarExtraAccess", targets: ["MenuBarExtraAccess"])
    ],
    traits: [
        .trait(name: "DebugLogging"),
        .default(enabledTraits: [])
    ],
    targets: [
        .target(
            name: "MenuBarExtraAccess",
            swiftSettings: [
                .define("MENUBAREXTRAACCESS_DEBUG_LOGGING", .when(traits: ["DebugLogging"]))
            ]
        )
    ]
)
