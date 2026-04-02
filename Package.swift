// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MotionDeskAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MotionDeskAgent",
            path: "Sources/MotionDeskAgent",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
