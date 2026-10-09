// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sightline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sightline",
            path: "Sources/Sightline"
        )
    ]
)
