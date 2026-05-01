// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DinkyCoreImage",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "DinkyCoreImage",
            targets: ["DinkyCoreImage"]
        ),
        .library(
            name: "DinkyCLILib",
            targets: ["DinkyCLILib"]
        ),
        .executable(
            name: "dinky",
            targets: ["DinkyCLIApp"]
        ),
    ],
    targets: [
        .target(
            name: "DinkyCoreImage",
            path: "Sources/DinkyCoreImage"
        ),
        .target(
            name: "DinkyCLILib",
            dependencies: ["DinkyCoreImage"],
            path: "Sources/DinkyCLILib"
        ),
        .executableTarget(
            name: "DinkyCLIApp",
            dependencies: ["DinkyCLILib"],
            path: "Sources/DinkyCLIApp"
        ),
        .testTarget(
            name: "DinkyCLILibTests",
            dependencies: ["DinkyCLILib", "DinkyCoreImage"],
            path: "Tests/DinkyCLILibTests"
        ),
    ]
)
