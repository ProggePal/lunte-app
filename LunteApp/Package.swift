// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunteApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../LunteCore"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lunte",
            dependencies: [
                .product(name: "LunteCore", package: "LunteCore"),
                .product(name: "Sparkle", package: "Sparkle"),
                "LayaKit",
                "FuseKit",
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(name: "FuseKit"), // the menu bar fuse, in a library so Xcode can preview it
        .testTarget(name: "FuseKitTests", dependencies: ["FuseKit"]),
        .target(name: "LayaKit", exclude: ["LICENSE", "README.md"]), // FluidUse's Laya runtime, vendored (see its README)
    ],
    swiftLanguageModes: [.v5] // ponytail: prototype; Swift 6 strict concurrency when it matters
)
