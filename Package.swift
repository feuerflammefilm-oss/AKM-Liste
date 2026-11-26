// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AKMListe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AKMListe",
            path: "Sources/AKMListe"
        )
    ]
)
