import Foundation
import CubeSolver3
import CubeCore
import Testing
@testable import CubeSession

@Test("R15: practice starts with the documented complete scramble, separate from real input")
func practiceExampleDraft() throws {
  let example = try PracticeExample.draft()
  #expect(example.missingCount == 0)
  let faces = try example.canonicalFacelets()
  #expect(faces.notation == "UULUUFRDDLRULRRLRRFFFUFFDFFFUUDDDDDDBLULLBLLRBRRBBBBBB")
  #expect(try CubeValidation.validate(faces).get().facelets == faces)
  let edited = try example.setting(face: .up, row: 0, column: 0, color: nil)
  #expect(edited.missingCount == 1)
  #expect(try PracticeExample.draft() == example)
}

@Test("R15/R18: memory-only stores isolate practice drafts and revoke deleted producers")
func practiceMemoryStorage() async throws {
  let first = SessionStore()
  let second = SessionStore()
  let example = try PracticeExample.draft()
  let lease = await first.currentLease()
  try await first.saveDraft(example, lease: lease)
  #expect(try await first.restore().session.draft == example)
  #expect(try await second.restore().session.phase == .home)
  var preferences = AppPreferences()
  preferences.effects = true
  try await first.savePreferences(preferences, lease: lease)
  #expect(try await first.loadPreferences() == preferences)
  #expect(try await second.loadPreferences() == AppPreferences())
  _ = try await first.delete(lease: lease)
  #expect(try await first.restore().session.phase == .home)
  #expect(try await first.loadPreferences() == AppPreferences())
  await #expect(throws: SessionStoreError.staleLease) {
    try await first.saveDraft(example, lease: lease)
  }
}

@MainActor @Test("R15: practice uses real solving and deletion without modifying the saved real cube")
func practiceRealWorkflowIsolation() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let realDraft = ManualDraft(palette: try archivePalette(), revision: 10)
  try await real.saveDraft(realDraft, lease: real.currentLease())
  let file = directory.appendingPathComponent("draft.json")
  let before = try Data(contentsOf: file)
  let memory = SessionStore()
  let example = try PracticeExample.draft()
  try await memory.saveDraft(example, lease: memory.currentLease())
  let controller = SessionController(storage: memory, solver: SolverService())
  await controller.load()
  #expect(controller.session.phase == .editing)
  #expect(controller.send(.validateDraft) == .accepted)
  #expect(controller.session.phase == .offer)
  #expect(controller.send(.consent(true)) == .accepted)
  await controller.waitForEffects()
  let plan = try #require(controller.session.plan)
  #expect(plan.original == (try example.canonicalFacelets()))
  #expect(plan.original.applying(plan.moves) == .solved)
  #expect(controller.session.phase == .guide)
  #expect(try await memory.restore().session.phase == .resumeCheck)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(try await memory.restore().session.phase == .home)
  #expect(try Data(contentsOf: file) == before)
  #expect(try await real.restore().session.draft == realDraft)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["draft.json"])
}

@MainActor @Test("R15: opening practice prepares a separate editable example with copied preferences")
func practiceLifecycleStart() async throws {
  var preferences = AppPreferences()
  preferences.speed = .slow
  preferences.narration = false
  let practice = try await PracticeSession.start(preferences: preferences)
  #expect(practice.controller.loadStatus == .ready)
  #expect(practice.controller.session.phase == .editing)
  #expect(practice.controller.session.draft == (try PracticeExample.draft()))
  #expect(practice.controller.preferences == preferences)
  practice.close()
  await practice.controller.waitForEffects()
  #expect(practice.controller.session.phase == .home)
  #expect(!practice.controller.session.hasWork)
}

@MainActor @Test("R15: exiting practice cancels solving and rejects a late verified result")
func practiceExitDuringSolve() async throws {
  let gate = ControllerGate()
  let solver = HeldControllerSolver(gate)
  let practice = try await PracticeSession.start(preferences: AppPreferences(), solver: solver)
  try #require(practice.controller.send(.validateDraft) == .accepted)
  try #require(practice.controller.send(.consent(true)) == .accepted)
  await gate.waitUntilEntered()
  practice.close()
  await gate.release()
  await practice.controller.waitForEffects()
  #expect(await solver.sawCancellation)
  #expect(practice.controller.session.phase == .home)
  #expect(practice.controller.session.plan == nil)
  #expect(!practice.controller.session.hasWork)
  let next = try await PracticeSession.start(preferences: AppPreferences())
  #expect(next.controller.session.phase == .editing)
  #expect(next.controller.session.plan == nil)
}
