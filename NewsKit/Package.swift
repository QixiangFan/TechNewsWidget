// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NewsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NewsKit", targets: ["NewsKit"]),
    ],
    targets: [
        // Shared fetching / parsing / caching code used by the app and the widget.
        .target(name: "NewsKit"),
        // Command-line tool that prints what every source returns. Run with `swift run newsdump`.
        .executableTarget(name: "newsdump", dependencies: ["NewsKit"]),
        // Offline parser / cache tests with inline fixtures. Run with `swift test`.
        .testTarget(name: "NewsKitTests", dependencies: ["NewsKit"]),
    ]
)
