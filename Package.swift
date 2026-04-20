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
        .testTarget(
            name: "ModelSwitchboardCoreTests",
            dependencies: ["ModelSwitchboardCore"]
        ),
        .testTarget(
            name: "ModelSwitchboardAppTests",
            dependencies: ["ModelSwitchboardApp"]
        ),
    ]
)
