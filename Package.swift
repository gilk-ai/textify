// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Textify",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Textify",
            path: "Sources/Textify"
        )
    ]
)
