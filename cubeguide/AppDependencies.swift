import CubeCore
import CubeSession
import CubeSolver3
import Foundation

/// Composition boundary shared by app adapters; cube mathematics stays in CubeKit.
struct AppDependencies {
  let solver = SolverService()
  let canonicalFaces: [Face] = Face.allCases
  let sessionStore: SessionStore
  static var guideDirectory: URL {
    URL.applicationSupportDirectory.appendingPathComponent(storeName, isDirectory: true)
  }
  #if DEBUG
    // UI tests on a physical device must never read or delete the owner's saved cube.
    private static var storeName: String {
      ProcessInfo.processInfo.environment["CUBEGUIDE_UI_TEST_STORE"] == nil
        ? "CubeGuide/Guide" : "CubeGuide/UITestGuide"
    }
  #else
    private static let storeName = "CubeGuide/Guide"
  #endif
  func makeSessionController(playback: (any GuidePlayback)? = nil, camera: (any ScanCamera)? = nil)
    -> SessionController
  {
    SessionController(storage: sessionStore, solver: solver, playback: playback, camera: camera)
  }
  func restoreSession() async throws -> SessionRestoration {
    try await sessionStore.restore()
  }
  init(guideDirectory: URL = Self.guideDirectory) {
    sessionStore = SessionStore(directory: guideDirectory)
  }
}
