// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Floater",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(name: "Floater", path: "Sources/Floater")
    ]
)
