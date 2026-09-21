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
    URL.applicationSupportDirectory.appendingPathComponent("CubeGuide/Guide", isDirectory: true)
  }
  func makeSessionController(playback: any GuidePlayback) -> SessionController {
    SessionController(storage: sessionStore, solver: solver, playback: playback)
  }
  func restoreSession() async throws -> SessionRestoration {
    try await sessionStore.restore()
  }
  init(guideDirectory: URL = Self.guideDirectory) {
    sessionStore = SessionStore(directory: guideDirectory)
  }
}
