// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lanewise",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lanewise",
            path: "Sources/Lanewise"
        )
    ]
)
