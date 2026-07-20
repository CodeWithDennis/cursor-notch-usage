// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorNotchUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CursorNotchUsage",
            path: "Sources/CursorNotchUsage"
        )
    ]
)
