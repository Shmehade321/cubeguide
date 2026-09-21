import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@Test("R18: durable discard removes scan input, preserves guide bytes and rejects prior producers")
func draftDiscardRetainsGuide() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  let lease = await store.currentLease()
  try await store.save(guide, palette: archivePalette(), lease: lease)
  let bytes = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  let scan = try pendingScan(purpose: .recovery, guide: guide.id)
  try await store.saveScanDraft(scan, lease: lease)
  let renewed = try await store.discardDraft(revision: 11, lease: lease)
  #expect(renewed != lease)
  let restored = try await SessionStore(directory: directory).restore()
  #expect(restored.pendingScan == nil)
  #expect(restored.session.guideProgress == guide.progress)
  #expect(restored.session.latestInputRevision == 11)
  #expect(!restored.session.aligned)
  #expect(try Data(contentsOf: directory.appendingPathComponent("guide.json")) == bytes)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.saveScanDraft(scan, lease: lease)
  }
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.saveScanDraft(scan, lease: renewed)
  }
  let home = apply(restored.session, .cancel).session
  let started = apply(home, .startManual(replacing: true))
  #expect(started.session.revision == 12)
}

@Test("R18: discard survives relaunch of partial and empty manual entry without reviving old work")
func draftDiscardManual() async throws {
  for hasDraft in [false, true] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    try await store.startManual(revision: 4, lease: store.currentLease())
    if hasDraft {
      try await store.saveDraft(
        ManualDraft(palette: archivePalette(), revision: 5), lease: store.currentLease())
    }
    _ = try await store.discardDraft(revision: 6, lease: store.currentLease())
    let restored = try await SessionStore(directory: directory).restore()
    #expect(restored.session.phase == .home && !restored.session.hasWork)
    #expect(restored.session.draft == nil)
    #expect(restored.session.latestInputRevision == 6)
    let start = apply(restored.session, .startManual(replacing: false))
    #expect(start.session.revision == 7)
    try await store.startManual(revision: start.session.revision, lease: store.currentLease())
    #expect(try await store.restore().session.phase == .editing)
  }
}

private enum DiscardFailure: Error { case interrupted }
@Test(
  "V11: discard failure keeps a complete old/new record, invalidates producers and resynchronizes retry"
)
func draftDiscardBoundaries() async throws {
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    let scan = try pendingScan()
    try await store.saveScanDraft(scan, lease: store.currentLease())
    let failing = SessionStore(directory: directory) {
      if $0 == boundary { throw DiscardFailure.interrupted }
    }
    let oldLease = await failing.currentLease()
    await #expect(throws: DiscardFailure.self) {
      try await failing.discardDraft(revision: 11, lease: oldLease)
    }
    #expect(await failing.currentLease() != oldLease)
    let reopened = SessionStore(directory: directory)
    #expect(try await reopened.restore().pendingScan == (boundary == .afterReplace ? nil : scan))
    _ = try await reopened.discardDraft(revision: 11, lease: reopened.currentLease())
    #expect(try await reopened.restore().pendingScan == nil)
    // Even an identical retry must pass through synchronization, not return early.
    await #expect(throws: DiscardFailure.self) {
      try await failing.discardDraft(revision: 11, lease: failing.currentLease())
    }
  }
}

@MainActor
@Test(
  "R18: confirmed controller discard stops camera, rejects late frames and permits higher-revision input"
)
func draftDiscardController() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: store, solver: CubeSolver3.SolverService(), playback: RecordingPlayback(),
    camera: camera)
  await controller.load()
  #expect(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  #expect(controller.sendScan(.capture) == .accepted)
  let callback = try #require(camera.completions.last)
  #expect(controller.discardDraft(confirmed: false) == .rejected(.confirmationRequired))
  #expect(controller.discardDraft(confirmed: true) == .accepted)
  #expect(controller.discardStatus == .saving && !controller.isCameraReady)
  #expect(controller.sendScan(.resume(confirmedUnchanged: true)) == .rejected(.unavailableEvent))
  callback(.captured(try #require(pendingScan().draft.faces[2])))
  await controller.waitForEffects()
  #expect(controller.discardStatus == .idle && controller.scanWorkflow == nil)
  #expect(controller.session.phase == .home && !controller.session.hasWork)
  let floor = controller.session.latestInputRevision
  #expect(floor == 2)
  #expect(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  #expect(controller.pendingScan?.draft.revision == floor + 1)
  callback(.failed(.captureFailed))
  #expect(controller.scanWorkflow?.phase == .scanning)
}

@MainActor
@Test("R18: discard serializes behind an in-flight draft write and ignores its late success")
func draftDiscardDuringSave() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate), solver: CubeSolver3.SolverService(),
    playback: RecordingPlayback())
  await controller.load()
  #expect(controller.send(.startManual(replacing: false)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.send(.editDraft(.centers(try archivePalette()))) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.discardDraft(confirmed: true) == .accepted)
  #expect(controller.discardStatus == .saving)
  #expect(controller.session.draft != nil)
  #expect(controller.send(.validateDraft) == .rejected(.unavailableEvent))
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && controller.session.draft == nil)
  #expect(try await real.loadDraft() == nil)
}

@MainActor
@Test(
  "R18: a failed discard cannot be undone in memory; retry settles it or deletion supersedes it")
func draftDiscardRetryAndDelete() async throws {
  for delete in [false, true] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = SessionStore(directory: directory)
    try await real.saveDraft(
      ManualDraft(palette: archivePalette(), revision: 5), lease: real.currentLease())
    let storage = ControlledStorage(real)
    await storage.configureDiscard(fail: true)
    let controller = SessionController(
      storage: storage, solver: SolverService(), playback: RecordingPlayback())
    await controller.load()
    #expect(controller.discardDraft(confirmed: true) == .accepted)
    await controller.waitForEffects()
    #expect(controller.discardStatus == .failed && controller.lastError != nil)
    #expect(controller.session.draft != nil)
    #expect(try await real.restore().session.phase == .home)
    #expect(controller.send(.cancel) == .rejected(.unavailableEvent))
    #expect(controller.send(.retryDraftSave) == .rejected(.unavailableEvent))
    let gate = ControllerGate()
    await storage.configureDiscard(gate: gate)
    #expect(controller.retryDraftDiscard() == .accepted)
    await gate.waitUntilEntered()
    if delete { #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted) }
    await gate.release()
    await controller.waitForEffects()
    #expect(controller.discardStatus == .idle && controller.session.phase == .home)
    #expect(controller.lastError == nil && controller.session.draft == nil)
    #expect(controller.session.latestInputRevision == 6)
    if delete {
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }
}

@Test(
  "V11: discard marker rejects malformed metadata and preserves unknown schemas until global deletion"
)
func draftDiscardArchiveGuards() async throws {
  let marker = try DiscardedDraft(revision: 11, retainedGuide: SaveID(revision: 3, sequence: 1))
  let bytes = try CheckedArchive.encode(DraftRecord.discarded(marker))
  #expect(try DraftArchive.decodeRecord(bytes) == .discarded(marker))
  #expect(throws: ArchiveError.invalidProgress) { try DraftArchive.decode(bytes) }
  #expect(throws: ArchiveError.invalidProgress) { try DraftArchive.decodeScan(bytes) }
  for bad: [String: Any] in [
    ["revision": 0], ["revision": 11, "retainedGuide": ["revision": 11, "sequence": 1]],
    ["revision": 11, "retainedGuide": ["revision": 3, "sequence": 0]],
  ] {
    #expect(throws: (any Error).self) {
      try DraftArchive.decodeRecord(mutatedArchive(bytes, payload: { $0["discarded"] = bad }))
    }
  }
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  for invalid in [Data("invalid".utf8), try mutatedArchive(bytes, envelope: { $0["schema"] = 2 })] {
    let path = directory.appendingPathComponent("draft.json")
    try invalid.write(to: path)
    let lease = await store.currentLease()
    await #expect(throws: (any Error).self) {
      try await store.discardDraft(revision: 12, lease: lease)
    }
    #expect(try Data(contentsOf: path) == invalid)
    #expect(await store.currentLease() == lease)
  }
  _ = try await store.delete(lease: store.currentLease())
  #expect(try await store.restore().session == Session())
}

@Test(
  "R11/R18: retained guidance can advance after discard, but discarded-input plans and stale retries cannot"
)
func draftDiscardGuideOrdering() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let original = try #require(try preparingSession().pendingSave)
  try await store.save(original, palette: archivePalette(), lease: store.currentLease())
  try await store.saveScanDraft(
    pendingScan(purpose: .recovery, guide: original.id), lease: store.currentLease())
  _ = try await store.discardDraft(revision: 11, lease: store.currentLease())
  let restored = try await store.restore()
  let preparation = try #require(apply(restored.session, .compare(.after)).session.pendingSave)
  #expect(preparation.id.revision == original.id.revision)
  try await store.save(preparation, palette: archivePalette(), lease: store.currentLease())
  #expect(try await store.restore().session.latestInputRevision == 11)
  for revision: UInt64 in [10, 11, 12] {
    let request = try GuideSaveRequest(
      id: SaveID(revision: revision, sequence: 1), kind: .preparation,
      progress: GuideProgress(plan: original.progress.plan, revision: revision),
      pendingPrepared: true)
    if revision < 12 {
      await #expect(throws: SessionStoreError.staleWrite) {
        try await store.save(request, palette: archivePalette(), lease: store.currentLease())
      }
    } else {
      try await store.save(request, palette: archivePalette(), lease: store.currentLease())
      #expect(try await store.restore().session.revision == 12)
      await #expect(throws: SessionStoreError.staleWrite) {
        try await store.discardDraft(revision: 11, lease: store.currentLease())
      }
    }
  }
  // A retained-guide marker cannot silently restore without the guide it identifies.
  try FileManager.default.removeItem(at: directory.appendingPathComponent("guide.json"))
  await #expect(throws: SessionStoreError.conflictingRecords) { try await store.restore() }
}
