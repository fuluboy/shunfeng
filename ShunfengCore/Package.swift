// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShunfengCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShunfengCore", targets: ["ShunfengCore"]),
        .executable(name: "shunfeng-listen", targets: ["shunfeng-listen"]),
    ],
    targets: [
        .target(name: "ShunfengCore"),
        .executableTarget(name: "shunfeng-listen", dependencies: ["ShunfengCore"]),
        .testTarget(name: "ShunfengCoreTests", dependencies: ["ShunfengCore"]),
    ]
)
