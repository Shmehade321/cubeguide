import CubeCore
import CubeScan
import CubeSession
import CubeSolver3
import Foundation
import Testing

@testable import cubeguide

struct AppCompositionTests {
  @MainActor
  @Test("R20: app links CubeCore and exposes all canonical faces")
  func packageIntegration() {
    #expect(AppDependencies().canonicalFaces.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
  }

  @MainActor
  @Test("R06: installed app loads bundled tables and independently verifies a literal scramble")
  func bundledSolverIntegration() async throws {
    let faces = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    let cube = try CubeValidation.validate(faces).get()
    let response = await AppDependencies().solver.solve(cube, revision: 42)
    #expect(response.revision == 42)
    guard case .verified(let plan) = response.outcome else {
      Issue.record("App must produce a verified plan using its bundled solver resources")
      return
    }
    #expect(plan.original == faces)
    #expect(!plan.moves.isEmpty)
    #expect(faces.applying(plan.moves) == .solved)
  }
}

@MainActor
@Test(
  "R18: app guide store saves offline and restores; protection attributes checked on physical devices"
)
func protectedGuideStorage() async throws {
  let directory = AppDependencies.guideDirectory.appendingPathComponent("test-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  #expect(directory.path.hasPrefix(URL.applicationSupportDirectory.path + "/"))
  let dependencies = AppDependencies(guideDirectory: directory)
  let faces = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
  var session = Session()
  session = SessionReducer.reduce(session, event: .startManual(replacing: false)).session
  session =
    SessionReducer.reduce(session, event: .manualStarted(try #require(session.pendingManualStart)))
    .session
  session = SessionReducer.reduce(session, event: .validate(faces)).session
  session = SessionReducer.reduce(session, event: .consent(true)).session
  let cube = try #require(session.confirmedCube)
  let result = await dependencies.solver.solve(cube, revision: session.revision)
  session = SessionReducer.reduce(session, event: .solveResult(result)).session
  let request = try #require(session.pendingSave)
  let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  let store = dependencies.sessionStore
  let partial = try ManualDraft(palette: palette, revision: 0)
    .setting(face: .front, row: 0, column: 2, color: .blue)
  try await store.saveDraft(partial, lease: store.currentLease())
  #expect(try await store.loadDraft() == partial)
  #expect(try await dependencies.restoreSession().session.draft == partial)
  try await store.save(request, palette: palette, lease: store.currentLease())
  // Simulator does not expose the protection attribute on this runtime.
  // Physical qualification must run these assertions and locked-device I/O checks.
  #if !targetEnvironment(simulator)
    let path = directory.appendingPathComponent("guide.json").path
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect(attributes[.protectionKey] as? String == FileProtectionType.complete.rawValue)
    let folderAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect(folderAttributes[.protectionKey] as? String == FileProtectionType.complete.rawValue)
  #endif
  #expect(
    try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  let restored = try #require(try await store.load())
  #expect(restored.progress == request.progress)
  #expect(restored.palette == palette)
  let snapshot = try await dependencies.restoreSession()
  #expect(snapshot.palette == palette)
  let resumed = snapshot.session
  #expect(resumed.phase == .resumeCheck && !resumed.aligned)
  _ = try await store.delete(lease: store.currentLease())
  #expect(try await store.load() == nil)
  #expect(try await store.loadDraft() == nil)
  #expect(try await dependencies.restoreSession().session.phase == .home)
}

@MainActor
private final class CompositionPlayback: GuidePlayback {
  var stopCount = 0
  func play(
    _ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void
  ) {
    Issue.record("This storage-only integration must not start playback")
  }
  func pause() { Issue.record("This storage-only integration must not pause playback") }
  func stop() { stopCount += 1 }
}

@MainActor
@Test("R05/R18: app composition executes draft-save and delete commands through the coordinator")
func appSessionCoordinator() async throws {
  let directory = AppDependencies.guideDirectory.appendingPathComponent("coordinator-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let dependencies = AppDependencies(guideDirectory: directory)
  let playback = CompositionPlayback()
  let controller = dependencies.makeSessionController(playback: playback)
  await controller.load()
  #expect(controller.send(.startManual(replacing: false)) == .accepted)
  let startDeadline = ContinuousClock.now.advanced(by: .seconds(10))
  while controller.session.phase == .startingManual && ContinuousClock.now < startDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(controller.session.phase == .editing)
  let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  #expect(controller.send(.editDraft(.centers(palette))) == .accepted)
  let saveDeadline = ContinuousClock.now.advanced(by: .seconds(10))
  while controller.session.phase == .savingDraft && ContinuousClock.now < saveDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(controller.session.phase == .editing)
  #expect(try await dependencies.sessionStore.loadDraft() == controller.session.draft)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  let deleteDeadline = ContinuousClock.now.advanced(by: .seconds(10))
  while controller.session.phase == .deleting && ContinuousClock.now < deleteDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  #expect(try await dependencies.sessionStore.loadDraft() == nil)
  #expect(playback.stopCount == 1)
}

@MainActor
@Test("R05/R10: installed app persists entered-color completion and mismatch recovery")
func appEnteredCompletion() async throws {
  let directory = AppDependencies.guideDirectory.appendingPathComponent("completion-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let dependencies = AppDependencies(guideDirectory: directory)
  let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  var draft = ManualDraft(palette: palette)
  for face in Face.allCases {
    for row in 0..<3 {
      for column in 0..<3 where row != 1 || column != 1 {
        draft = try draft.setting(
          face: face, row: row, column: column, color: palette.colors[Int(face.rawValue)])
      }
    }
  }
  try await dependencies.sessionStore.saveDraft(
    draft, lease: dependencies.sessionStore.currentLease())
  let controller = dependencies.makeSessionController(playback: CompositionPlayback())
  await controller.load()
  #expect(controller.send(.validateDraft) == .accepted)
  #expect(controller.session.phase == .alreadySolved)
  #expect(controller.send(.confirmCompletion) == .accepted)
  let deadline = ContinuousClock.now.advanced(by: .seconds(10))
  while controller.session.phase == .savingCompletion && ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(
    controller.session.phase == .completed && controller.session.completion == .enteredColorsSolved)
  let relaunched = dependencies.makeSessionController(playback: CompositionPlayback())
  await relaunched.load()
  #expect(
    relaunched.session.phase == .completed && relaunched.session.completion == .enteredColorsSolved)
  #expect(relaunched.send(.mismatch) == .accepted)
  let recoveryDeadline = ContinuousClock.now.advanced(by: .seconds(10))
  while relaunched.session.phase == .savingRecovery && ContinuousClock.now < recoveryDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(relaunched.session.phase == .recovery && relaunched.session.completion == nil)
  let restoredRecovery = try await dependencies.restoreSession().session
  #expect(restoredRecovery.phase == .recovery && restoredRecovery.recoveryRequired)
}
