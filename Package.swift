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
    ]
)
