// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CubeKit",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "CubeCore", targets: ["CubeCore"]),
               .library(name: "CubeSolver3", targets: ["CubeSolver3"]),
               .library(name: "CubeSession", targets: ["CubeSession"])],
    targets: [
        .target(name: "CubeCore"),
        .target(name: "CubeSession", dependencies: ["CubeCore", "CubeSolver3"]),
        .testTarget(name: "CubeSessionTests", dependencies: ["CubeSession", "CubeCore", "CubeSolver3"]),
        .executableTarget(name: "SolverBenchmark", dependencies: ["CubeSolver3", "CubeCore"]),
        .executableTarget(name: "TableGenerator", dependencies: ["CubeTableTools", "CubeSolver3"]),
        .target(name: "CubeTableTools", dependencies: ["CubeSolver3", "CubeCore"]),
        .testTarget(name: "CubeTableToolsTests", dependencies: ["CubeTableTools", "CubeSolver3"]),
        .target(name: "CubeSolver3", dependencies: ["CubeCore"], resources: [.copy("Resources/Tables")]),
        .testTarget(name: "CubeSolver3Tests", dependencies: ["CubeSolver3", "CubeCore"]),
        .testTarget(name: "CubeCoreTests", dependencies: ["CubeCore"])
    ],
    swiftLanguageModes: [.v6]
)
