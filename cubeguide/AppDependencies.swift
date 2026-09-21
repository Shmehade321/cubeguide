import CubeCore
import CubeSession
import CubeSolver3
import Foundation

/// Composition boundary shared by app adapters; cube mathematics stays in CubeKit.
struct AppDependencies {
  let solver = SolverService()
  let canonicalFaces: [Face] = Face.allCases
  let guideStore: GuideStore
  static var guideDirectory: URL {
    URL.applicationSupportDirectory.appendingPathComponent("CubeGuide/Guide", isDirectory: true)
  }
  init(guideDirectory: URL = Self.guideDirectory) {
    guideStore = GuideStore(directory: guideDirectory)
  }
}
