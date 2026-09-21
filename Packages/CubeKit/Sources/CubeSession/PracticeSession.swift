import CubeSolver3

/// Owns a fictional, ephemeral workflow independently of the user's real session.
@MainActor
public final class PracticeSession {
  public let controller: SessionController
  private init(controller: SessionController) { self.controller = controller }
  public static func start(
    preferences: AppPreferences, solver: any SessionSolving = SolverService(),
    playback: (any GuidePlayback)? = nil
  ) async throws -> PracticeSession {
    let storage = SessionStore()
    let lease = await storage.currentLease()
    try await storage.saveDraft(PracticeExample.draft(), lease: lease)
    try await storage.savePreferences(preferences, lease: lease)
    let controller = SessionController(storage: storage, solver: solver, playback: playback)
    await controller.load()
    if let error = controller.lastError { throw error }
    return PracticeSession(controller: controller)
  }
  public func close() {
    controller.send(.deleteLocalData(confirmed: true))
  }
}
