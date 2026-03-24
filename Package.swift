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
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "ClipiaryLib",
            path: "Sources/ClipiaryLib"
        ),
        .executableTarget(
            name: "ClipiaryApp",
            dependencies: ["ClipiaryLib"],
            path: "Sources/ClipiaryApp"
        ),
        .testTarget(
            name: "ClipiaryTests",
            dependencies: [
                "ClipiaryLib",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/ClipiaryTests"
        ),
    ]
)
