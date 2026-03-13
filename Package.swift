// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipiary",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Clipiary",
            targets: ["ClipiaryApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ClipiaryApp",
            path: "Sources/ClipiaryApp"
        ),
    ]
)
