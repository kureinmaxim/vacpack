// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CompressorKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CompressorKit", targets: ["CompressorKit"]),
        .executable(name: "vacpack", targets: ["vacpack"]),
    ],
    targets: [
        .target(name: "CompressorKit"),
        .executableTarget(name: "vacpack", dependencies: ["CompressorKit"]),
        .testTarget(name: "CompressorKitTests", dependencies: ["CompressorKit"]),
    ]
)
