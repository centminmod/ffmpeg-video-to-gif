// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VidConvert",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/ConverterEngine")
    ],
    targets: [
        .executableTarget(
            name: "VidConvert",
            dependencies: [.product(name: "ConverterEngine", package: "ConverterEngine")])
    ]
)
