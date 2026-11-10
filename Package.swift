// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Floater",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Floater", path: "Sources/Floater")
    ]
)
