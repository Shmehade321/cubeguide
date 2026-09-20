import CubeCore

/// Composition boundary shared by app adapters; cube mathematics stays in CubeKit.
struct AppDependencies {
    let canonicalFaces: [Face] = Face.allCases
}
