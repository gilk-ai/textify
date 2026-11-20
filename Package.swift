// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Textify",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Textify",
            path: "Sources/Textify",
            linkerSettings: [
                // FoundationModels (on-device LLM for file labels) exists only on macOS 26+.
                // Weak-link it so the app still launches on macOS 14/15, where labels use a heuristic.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            ]
        )
    ]
)
