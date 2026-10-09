// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Recall",
            path: "Sources/Recall"
        )
    ]
)
