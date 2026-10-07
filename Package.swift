// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Clipline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clipline", path: "Sources/Clipline")
    ]
)
