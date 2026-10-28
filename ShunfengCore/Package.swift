// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShunfengCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShunfengCore", targets: ["ShunfengCore"]),
    ],
    targets: [
        .target(name: "ShunfengCore"),
        .testTarget(name: "ShunfengCoreTests", dependencies: ["ShunfengCore"]),
    ]
)
