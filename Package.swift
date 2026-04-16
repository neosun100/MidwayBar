// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MidwayBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MidwayBar",
            path: "MidwayBar"
        )
    ]
)
