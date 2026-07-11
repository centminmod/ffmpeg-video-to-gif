// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ConverterEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConverterEngine", targets: ["ConverterEngine"])
    ],
    targets: [
        .target(name: "ConverterEngine"),
        .testTarget(name: "ConverterEngineTests", dependencies: ["ConverterEngine"])
    ]
)
