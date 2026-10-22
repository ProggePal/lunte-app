// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunteCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LunteCore", targets: ["LunteCore"]),
        .executable(name: "lunte-hook", targets: ["LunteHook"]),
    ],
    targets: [
        .target(name: "LunteCore"),
        .executableTarget(name: "LunteHook", dependencies: ["LunteCore"]),
        .testTarget(name: "LunteCoreTests", dependencies: ["LunteCore"]),
    ],
    swiftLanguageModes: [.v5] // ponytail: prototype; Swift 6 strict concurrency when it matters
)
