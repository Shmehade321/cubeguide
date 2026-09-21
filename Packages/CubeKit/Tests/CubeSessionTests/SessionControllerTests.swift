import CubeCore
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@MainActor
final class RecordingPlayback: GuidePlayback {
  var played: [(GuideAction, PlaybackID, Bool)] = []
  var completions: [@MainActor @Sendable (PlaybackID) -> Void] = []
  var stops = 0
  var pauses = 0
  func play(
    _ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void
  ) {
    played.append((action, id, restart))
    completions.append(finished)
  }
  func pause() { pauses += 1 }
  func stop() { stops += 1 }
}

@MainActor
@Test("R05/R09: coordinator saves each edit, solves only after consent and persists guidance")
func controllerRealFlow() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let playback = RecordingPlayback()
  let controller = SessionController(storage: store, solver: SolverService(), playback: playback)
  #expect(controller.send(.startManual(replacing: false)) == .rejected(.unavailableEvent))
  await controller.load()
  #expect(controller.loadStatus == .ready)
  #expect(controller.send(.startManual(replacing: false)) == .accepted)
  await controller.waitForEffects()
  let palette = try archivePalette()
  #expect(controller.send(.editDraft(.centers(palette))) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing)
  #expect(try await store.loadDraft() == controller.session.draft)
  let faces = try Facelets(notation: literalRight)
  for face in Face.allCases {
    for row in 0..<3 {
      for column in 0..<3 where row != 1 || column != 1 {
        let color = palette.colors[
          Int(faces.faces[Int(face.rawValue) * 9 + row * 3 + column].rawValue)]
        #expect(
          controller.send(.editDraft(.sticker(face: face, row: row, column: column, color: color)))
            == .accepted)
        await controller.waitForEffects()
      }
    }
  }
  #expect(controller.send(.validateDraft) == .accepted)
  #expect(controller.session.phase == .offer)
  #expect(try await store.load() == nil)
  #expect(controller.send(.consent(true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .guide)
  #expect(controller.session.preparationDurable)
  #expect(try await store.load()?.progress == controller.session.guideProgress)
  #expect(playback.played.isEmpty)
  #expect(controller.send(.confirmAlignment) == .accepted)
  #expect(controller.send(.play) == .accepted)
  let first = try #require(playback.played.first)
  playback.completions[0](first.1)
  #expect(controller.session.preview == .finished)
  #expect(controller.session.guideProgress?.acknowledgedActions == 0)
  #expect(controller.send(.acknowledge(first.0.id)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.guideProgress?.acknowledgedActions == 1)
  #expect(try await store.load()?.progress == controller.session.guideProgress)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  #expect(try await store.loadDraft() == nil)
  #expect(try await store.load() == nil)
  #expect(playback.stops > 0)
}

@MainActor @Test("R18: corrupt restore blocks edits and can be explicitly deleted")
func controllerRestoreFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent("draft.json")
  try Data("corrupt".utf8).write(to: file)
  let controller = SessionController(
    storage: SessionStore(directory: directory),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  #expect(controller.loadStatus == .failed)
  #expect(controller.lastError != nil)
  #expect(controller.send(.startManual(replacing: true)) == .rejected(.unavailableEvent))
  #expect(controller.send(.deleteLocalData(confirmed: false)) == .rejected(.confirmationRequired))
  #expect(try Data(contentsOf: file) == Data("corrupt".utf8))
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.loadStatus == .ready && controller.session.phase == .home)
  #expect(controller.lastError == nil)
  #expect(!FileManager.default.fileExists(atPath: file.path))
}

actor ControllerGate {
  private var entered = false
  private var released = false
  private var entrants: [CheckedContinuation<Void, Never>] = []
  private var blocked: CheckedContinuation<Void, Never>?
  func pause() async {
    entered = true
    entrants.forEach { $0.resume() }
    entrants.removeAll()
    if !released { await withCheckedContinuation { blocked = $0 } }
  }
  func waitUntilEntered() async {
    if !entered { await withCheckedContinuation { entrants.append($0) } }
  }
  func release() {
    released = true
    blocked?.resume()
    blocked = nil
  }
}

enum ControllerInjectedFailure: Error { case afterWrite, afterDeletion }
actor ControlledStorage: SessionStorage {
  let real: SessionStore
  var restoreGate: ControllerGate?
  let draftGate: ControllerGate?
  let startGate: ControllerGate?
  var failStart: Bool
  var failGuide: Bool
  var failDraft: Bool
  var failDelete: Bool
  var failDiscard = false
  var discardGate: ControllerGate?
  init(
    _ real: SessionStore, restoreGate: ControllerGate? = nil, draftGate: ControllerGate? = nil,
    failDraft: Bool = false, failDelete: Bool = false, failGuide: Bool = false,
    startGate: ControllerGate? = nil, failStart: Bool = false
  ) {
    self.real = real
    self.restoreGate = restoreGate
    self.draftGate = draftGate
    self.startGate = startGate
    self.failStart = failStart
    self.failGuide = failGuide
    self.failDraft = failDraft
    self.failDelete = failDelete
  }
  func startManual(revision: UInt64, lease: StorageLease) async throws {
    try await real.startManual(revision: revision, lease: lease)
    await startGate?.pause()
    if failStart {
      failStart = false
      throw ControllerInjectedFailure.afterWrite
    }
  }
  func restore() async throws -> SessionRestoration {
    let result = try await real.restore()
    let gate = restoreGate
    restoreGate = nil
    await gate?.pause()
    return result
  }
  func gateNextRestore(_ gate: ControllerGate) { restoreGate = gate }
  func currentLease() async -> StorageLease { await real.currentLease() }
  func save(_ request: GuideSaveRequest, palette: CenterPalette, lease: StorageLease) async throws {
    try await real.save(request, palette: palette, lease: lease)
    if failGuide {
      failGuide = false
      throw ControllerInjectedFailure.afterWrite
    }
  }
  func saveDraft(_ draft: ManualDraft, lease: StorageLease) async throws {
    try await real.saveDraft(draft, lease: lease)
    await draftGate?.pause()
    if failDraft {
      failDraft = false
      throw ControllerInjectedFailure.afterWrite
    }
  }
  func saveScanDraft(_ scan: PendingScan, lease: StorageLease) async throws {
    try await real.saveScanDraft(scan, lease: lease)
    await draftGate?.pause()
    if failDraft {
      failDraft = false
      throw ControllerInjectedFailure.afterWrite
    }
  }
  func configureDiscard(fail: Bool = false, gate: ControllerGate? = nil) {
    failDiscard = fail
    discardGate = gate
  }
  func discardDraft(revision: UInt64, lease: StorageLease) async throws -> StorageLease {
    let result = try await real.discardDraft(revision: revision, lease: lease)
    await discardGate?.pause()
    if failDiscard {
      failDiscard = false
      throw ControllerInjectedFailure.afterWrite
    }
    return result
  }
  func delete(lease: StorageLease) async throws -> StorageLease {
    let result = try await real.delete(lease: lease)
    if failDelete {
      failDelete = false
      throw ControllerInjectedFailure.afterDeletion
    }
    return result
  }
}

@MainActor @Test("R18: late restored work cannot reappear after confirmed deletion")
func controllerLateRestore() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let draft = ManualDraft(palette: try archivePalette(), revision: 9)
  try await real.saveDraft(draft, lease: real.currentLease())
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, restoreGate: gate),
    solver: SolverService(), playback: RecordingPlayback())
  let loading = Task { await controller.load() }
  await gate.waitUntilEntered()
  #expect(controller.loadStatus == .loading)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .home)
  await gate.release()
  await loading.value
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  #expect(controller.palette == nil)
  #expect(try await real.loadDraft() == nil)
  // New input uses the new lease, rather than the lease in the late snapshot.
  #expect(controller.send(.startManual(replacing: false)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.send(.editDraft(.centers(try archivePalette()))) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing)
  #expect(try await real.loadDraft() == controller.session.draft)
}

@MainActor
@Test("R18: deletion waits for an in-flight draft write and ignores its late acknowledgement")
func controllerDeleteDuringWrite() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.startManual(replacing: false))
  await controller.waitForEffects()
  controller.send(.editDraft(.centers(try archivePalette())))
  await gate.waitUntilEntered()
  #expect(controller.session.phase == .savingDraft)
  #expect(try await real.loadDraft() != nil)
  controller.send(.deleteLocalData(confirmed: true))
  #expect(controller.session.phase == .deleting)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  #expect(try await real.loadDraft() == nil)
}

@MainActor
@Test("V11: failed callbacks retain entered work and deletion retries use the rotated lease")
func controllerStorageRetries() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let controller = SessionController(
    storage: ControlledStorage(real, failDraft: true, failDelete: true),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.startManual(replacing: false))
  await controller.waitForEffects()
  controller.send(.editDraft(.centers(try archivePalette())))
  await controller.waitForEffects()
  #expect(controller.session.phase == .draftStorageError)
  #expect(controller.lastError != nil)
  #expect(try await real.loadDraft() == controller.session.draft)
  #expect(controller.send(.validateDraft) == .rejected(.unavailableEvent))
  #expect(controller.send(.retryDraftSave) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing && controller.lastError == nil)
  controller.send(.deleteLocalData(confirmed: true))
  await controller.waitForEffects()
  #expect(controller.session.phase == .deletionError)
  #expect(controller.session.hasWork && controller.lastError != nil)
  #expect(controller.send(.retryDeletion) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && controller.lastError == nil)
  #expect(try await real.loadDraft() == nil)
}

actor HeldControllerSolver: SessionSolving {
  let gate: ControllerGate
  private(set) var sawCancellation = false
  init(_ gate: ControllerGate) { self.gate = gate }
  func solve(_ cube: LegalCube, revision: UInt64, budget: SolveBudget) async -> SolverResponse {
    // Compute real verified output before deliberately delaying delivery.
    let result = await SolverService().solve(cube, revision: revision, budget: budget)
    await gate.pause()
    sawCancellation = Task.isCancelled
    return result
  }
}

@MainActor
@Test("R05/R18: cancellation reaches the solve task and late verified output cannot create a guide")
func controllerLateSolve() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let solver = HeldControllerSolver(gate)
  let controller = SessionController(storage: real, solver: solver, playback: RecordingPlayback())
  await controller.load()
  controller.send(.startManual(replacing: false))
  await controller.waitForEffects()
  controller.send(.validate(try Facelets(notation: literalRight)))
  controller.send(.consent(true))
  await gate.waitUntilEntered()
  controller.send(.deleteLocalData(confirmed: true))
  #expect(controller.session.phase == .deleting)
  await gate.release()
  await controller.waitForEffects()
  #expect(await solver.sawCancellation)
  #expect(controller.session.phase == .home && controller.session.plan == nil)
  #expect(try await real.load() == nil)
}

@MainActor
@Test(
  "R09/R10: restored guidance needs comparison; pause and replay callbacks never acknowledge a turn"
)
func controllerPlaybackLifecycle() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let original = try preparingSession()
  try await store.save(
    #require(original.pendingSave), palette: archivePalette(), lease: store.currentLease())
  let playback = RecordingPlayback()
  let controller = SessionController(storage: store, solver: SolverService(), playback: playback)
  await controller.load()
  #expect(controller.session.phase == .resumeCheck)
  #expect(controller.send(.play) == .rejected(.unavailableEvent))
  #expect(controller.send(.compare(.before)) == .accepted)
  controller.send(.play)
  let first = try #require(playback.played.first)
  controller.send(.pause)
  #expect(playback.pauses == 1)
  playback.completions[0](first.1)
  #expect(controller.session.preview == .paused)
  controller.send(.play)
  #expect(playback.played.count == 2 && !playback.played[1].2)
  controller.send(.replay)
  #expect(playback.played.count == 3 && playback.played[2].2)
  playback.completions[1](playback.played[1].1)
  #expect(controller.session.preview == .playing)
  playback.completions[2](playback.played[2].1)
  #expect(controller.session.preview == .finished)
  #expect(controller.session.guideProgress?.acknowledgedActions == 0)
  let stopsBeforeBackground = playback.stops
  controller.send(.background)
  #expect(playback.stops == stopsBeforeBackground + 1 && controller.session.phase == .resumeCheck)
  playback.completions[2](playback.played[2].1)
  #expect(controller.session.preview == .idle && !controller.session.aligned)
  controller.send(.cancel)
  #expect(controller.send(.startManual(replacing: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.palette == nil)
}

@MainActor
@Test("R09: absent palette produces an explicit save error rather than inventing display centers")
func controllerMissingPalette() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let controller = SessionController(
    storage: store, solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.startManual(replacing: false))
  await controller.waitForEffects()
  controller.send(.validate(try Facelets(notation: literalRight)))
  controller.send(.consent(true))
  await controller.waitForEffects()
  #expect(controller.session.phase == .storageError)
  #expect(controller.lastError as? SessionControllerError == .missingPalette)
  #expect(try await store.load() == nil)
}

@MainActor
@Test("V09/V11: ambiguous acknowledgement failure requires physical comparison before retry")
func controllerGuideFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let original = try preparingSession()
  try await real.save(
    #require(original.pendingSave), palette: archivePalette(), lease: real.currentLease())
  let controller = SessionController(
    storage: ControlledStorage(real, failGuide: true),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.compare(.before))
  let action = try #require(controller.session.pendingAction)
  controller.send(.acknowledge(action.id))
  await controller.waitForEffects()
  #expect(controller.session.phase == .storageError && controller.lastError != nil)
  #expect(controller.session.guideProgress?.acknowledgedActions == 0)
  #expect(try await real.load()?.progress.acknowledgedActions == 1)
  #expect(controller.send(.play) == .rejected(.unavailableEvent))
  #expect(controller.send(.compare(.after)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.guideProgress?.acknowledgedActions == 1)
  #expect(controller.session.phase == .guide && controller.session.preparationDurable)
  #expect(controller.lastError == nil)
  #expect(try await real.load()?.progress == controller.session.guideProgress)
}

@MainActor
@Test(
  "R05/V11: confirmed replacement survives relaunch before colors exist and retries an ambiguous save"
)
func controllerManualReplacement() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let old = try #require(try preparingSession().pendingSave)
  try await real.save(old, palette: archivePalette(), lease: real.currentLease())
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, startGate: gate, failStart: true),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.cancel)
  #expect(controller.send(.startManual(replacing: false)) == .rejected(.replacementRequired))
  #expect(try await real.restore().session.plan == old.progress.plan)
  #expect(controller.send(.startManual(replacing: true)) == .accepted)
  await gate.waitUntilEntered()
  #expect(
    controller.session.phase == .startingManual && controller.session.plan == old.progress.plan)
  #expect(
    controller.send(.editDraft(.centers(try archivePalette()))) == .rejected(.unavailableEvent))
  let restored = try await real.restore()
  #expect(
    restored.session.phase == .editing && restored.session.plan == nil && restored.palette == nil)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.session.phase == .manualStartError && controller.lastError != nil)
  #expect(controller.send(.retryManualStart) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing && controller.lastError == nil)
  #expect(
    controller.session.plan == nil && controller.palette == nil && controller.session.draft == nil)
  #expect(controller.session == restored.session)
  controller.send(.editDraft(.centers(try archivePalette())))
  await controller.waitForEffects()
  #expect(try await real.restore().session.draft == controller.session.draft)
}

@MainActor
@Test("R18: delete during a manual-start write removes the boundary and rejects its late success")
func controllerDeleteDuringManualStart() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, startGate: gate),
    solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  controller.send(.startManual(replacing: false))
  await gate.waitUntilEntered()
  controller.send(.deleteLocalData(confirmed: true))
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  #expect(try await real.restore().session == Session())
  #expect(
    !FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("manual-start.json").path))
}
