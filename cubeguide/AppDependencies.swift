import CubeCore
import CubeSolver3

/// Composition boundary shared by app adapters; cube mathematics stays in CubeKit.
struct AppDependencies {
  let solver = SolverService()
  let canonicalFaces: [Face] = Face.allCases
}
