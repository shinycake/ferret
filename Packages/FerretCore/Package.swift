// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FerretCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FerretCore", targets: ["FerretCore"]),
    ],
    targets: [
        .target(name: "FerretCore"),
        .testTarget(name: "FerretCoreTests", dependencies: ["FerretCore"]),
    ]
)
