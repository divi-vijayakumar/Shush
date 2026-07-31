// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Shush",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Shush", targets: ["Shush"]),
        // The packaged/install script exposes this as `shush`. SwiftPM build
        // products cannot differ from the GUI's `Shush` by case alone on macOS.
        .executable(name: "shush-cli", targets: ["ShushCLI"])
    ],
    targets: [
        .executableTarget(
            name: "Shush",
            path: "Sources/Shush"
        ),
        .executableTarget(
            name: "ShushCLI",
            path: "Sources/ShushCLI"
        ),
        .testTarget(
            name: "ShushTests",
            dependencies: ["Shush"],
            path: "Tests/ShushTests"
        )
    ]
)
