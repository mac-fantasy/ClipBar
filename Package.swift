// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipBar", targets: ["ClipBar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "ClipBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ClipBarTests", dependencies: ["ClipBar"]),
    ]
)
