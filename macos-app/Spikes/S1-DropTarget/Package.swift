// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DropTargetSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DropTargetSpike")
    ]
)
