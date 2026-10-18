// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CompressorKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CompressorKit", targets: ["CompressorKit"]),
        .executable(name: "mycompressor-cli", targets: ["mycompressor-cli"]),
    ],
    targets: [
        .target(name: "CompressorKit"),
        .executableTarget(name: "mycompressor-cli", dependencies: ["CompressorKit"]),
        .testTarget(name: "CompressorKitTests", dependencies: ["CompressorKit"]),
    ]
)
