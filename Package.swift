// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelSwitchboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ModelSwitchboardCore", targets: ["ModelSwitchboardCore"]),
        .executable(name: "ModelSwitchboardApp", targets: ["ModelSwitchboardApp"]),
        .executable(name: "ModelSwitchboardController", targets: ["ModelSwitchboardController"]),
        .executable(name: "BumpVersion", targets: ["BumpVersion"]),
        .executable(name: "CheckCycles", targets: ["CheckCycles"]),
    ],
    dependencies: [
        .package(path: "Vendor/MenuBarExtraAccess")
    ],
    targets: [
        .target(
            name: "ModelSwitchboardCore"
        ),
        .executableTarget(
            name: "ModelSwitchboardApp",
            dependencies: [
                "ModelSwitchboardCore",
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess")
            ]
        ),
        .target(
            name: "ModelSwitchboardControllerCore",
            dependencies: ["ModelSwitchboardCore"],
            linkerSettings: [.linkedFramework("Network")]
        ),
        .executableTarget(
            name: "ModelSwitchboardController",
            dependencies: ["ModelSwitchboardControllerCore"]
        ),
        .target(
            name: "BumpVersionCore",
            path: "Sources/BumpVersionCore"
        ),
        .executableTarget(
            name: "BumpVersion",
            dependencies: ["BumpVersionCore"],
            path: "Sources/BumpVersion"
        ),
        .target(
            name: "CheckCyclesCore",
            path: "Sources/CheckCyclesCore"
        ),
        .executableTarget(
            name: "CheckCycles",
            dependencies: ["CheckCyclesCore"],
            path: "Sources/CheckCycles"
        ),
        .target(
            name: "ModelSwitchboardTestSupport",
            dependencies: ["ModelSwitchboardCore"],
            path: "Tests/ModelSwitchboardTestSupport"
        ),
        .testTarget(
            name: "ModelSwitchboardCoreTests",
            dependencies: ["ModelSwitchboardCore", "ModelSwitchboardTestSupport"]
        ),
        .testTarget(
            name: "ModelSwitchboardAppTests",
            dependencies: ["ModelSwitchboardApp", "ModelSwitchboardTestSupport"]
        ),
        .testTarget(
            name: "ModelSwitchboardControllerTests",
            dependencies: ["ModelSwitchboardControllerCore", "ModelSwitchboardCore"]
        ),
        .testTarget(
            name: "BumpVersionCoreTests",
            dependencies: ["BumpVersionCore"]
        ),
        .testTarget(
            name: "CheckCyclesCoreTests",
            dependencies: ["CheckCyclesCore"]
        ),
    ]
)
