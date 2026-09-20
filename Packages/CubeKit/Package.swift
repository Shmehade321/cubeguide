// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CubeKit",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "CubeCore", targets: ["CubeCore"])],
    targets: [
        .target(name: "CubeCore"),
        .testTarget(name: "CubeCoreTests", dependencies: ["CubeCore"])
    ],
    swiftLanguageModes: [.v6]
)
