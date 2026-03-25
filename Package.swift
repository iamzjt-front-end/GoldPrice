// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "GoldPrice",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GoldPrice", targets: ["GoldPrice"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GoldPrice",
            dependencies: [],
            path: "Sources"
        )
    ]
)
