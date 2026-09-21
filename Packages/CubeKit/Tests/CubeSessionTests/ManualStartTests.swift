import CubeCore
import Foundation
import Testing

@testable import CubeSession

private enum ManualStartFailure: Error { case stopped }

@Test("V11: a durable empty manual entry supersedes the old guide before centers exist")
func manualStartStoreReplacement() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let old = try #require(try preparingSession().pendingSave)
  try await store.save(old, palette: archivePalette(), lease: store.currentLease())
  let revision = old.id.revision + 1
  try await store.startManual(revision: revision, lease: store.currentLease())
  let reopened = SessionStore(directory: directory)
  let restored = try await reopened.restore()
  #expect(restored.session.phase == .editing)
  #expect(restored.session.hasWork && restored.session.revision == revision)
  #expect(restored.session.plan == nil && restored.session.draft == nil && restored.palette == nil)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await reopened.save(old, palette: archivePalette(), lease: reopened.currentLease())
  }
  let draft = ManualDraft(palette: try archivePalette(), revision: revision + 1)
  try await reopened.saveDraft(draft, lease: reopened.currentLease())
  // A duplicate start callback cannot erase newer input.
  try await reopened.startManual(revision: revision, lease: reopened.currentLease())
  #expect(try await reopened.restore().session.draft == draft)
  let lease = await reopened.currentLease()
  _ = try await reopened.delete(lease: lease)
  #expect(try await reopened.restore().session == Session())
  await #expect(throws: SessionStoreError.staleLease) {
    try await reopened.startManual(revision: revision + 2, lease: lease)
  }
}

@Test("V11: interrupted manual replacement restores the old guide or the complete new empty editor")
func manualStartWriteBoundaries() async throws {
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let initial = SessionStore(directory: directory)
    let old = try #require(try preparingSession().pendingSave)
    try await initial.save(old, palette: archivePalette(), lease: initial.currentLease())
    let failing = SessionStore(directory: directory) { stage in
      if stage == boundary { throw ManualStartFailure.stopped }
    }
    await #expect(throws: ManualStartFailure.self) {
      try await failing.startManual(revision: old.id.revision + 1, lease: failing.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    let restored = try await reopened.restore()
    #expect(restored.session.phase == (boundary == .afterReplace ? .editing : .resumeCheck))
    #expect((restored.session.plan == nil) == (boundary == .afterReplace))
    try await reopened.startManual(revision: old.id.revision + 1, lease: reopened.currentLease())
    #expect(try await reopened.restore().session.phase == .editing)
  }
}

@Test(
  "V09: replacement retains old context until matching durable success and rejects stale callbacks")
func manualStartReducerBarrier() throws {
  let old = try durableGuide()
  let home = apply(apply(old, .cancel).session, .cancel).session
  let started = apply(home, .startManual(replacing: true))
  #expect(started.disposition == .accepted)
  #expect(started.session.phase == .startingManual)
  #expect(started.session.plan == old.plan)
  let id = try #require(started.session.pendingManualStart)
  #expect(id.revision == old.revision + 1)
  #expect(
    apply(started.session, .editDraft(.centers(try archivePalette()))).disposition
      == .rejected(.unavailableEvent))
  #expect(
    apply(started.session, .manualStarted(SaveID(revision: id.revision, sequence: 99))).disposition
      == .ignored)
  let failed = apply(started.session, .manualStartFailed(id)).session
  #expect(failed.phase == .manualStartError && failed.plan == old.plan)
  #expect(apply(failed, .cancel).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .retryManualStart)
  let nextID = try #require(retry.session.pendingManualStart)
  #expect(nextID.revision == id.revision && nextID.sequence > id.sequence)
  #expect(apply(retry.session, .manualStarted(id)).disposition == .ignored)
  let saved = apply(retry.session, .manualStarted(nextID)).session
  #expect(saved.phase == .editing && saved.hasWork)
  #expect(saved.plan == nil && saved.draft == nil && saved.confirmedCube == nil)
  #expect(saved.revision == id.revision)
  #expect(apply(saved, .manualStarted(nextID)).disposition == .ignored)
}

@Test("V09/R18: interruption waits for the start save and deletion invalidates its acknowledgement")
func manualStartInterruption() throws {
  let starting = apply(Session(), .startManual(replacing: false)).session
  let id = try #require(starting.pendingManualStart)
  #expect(apply(starting, .background).disposition == .ignored)
  let exiting = apply(starting, .cancel).session
  #expect(exiting.phase == .startingManual)
  let home = apply(exiting, .manualStarted(id)).session
  #expect(home.phase == .home && home.hasWork)
  #expect(apply(home, .resume).session.phase == .editing)
  let deleted = apply(starting, .deleteLocalData(confirmed: true)).session
  #expect(deleted.pendingManualStart == nil)
  #expect(apply(deleted, .manualStarted(id)).disposition == .ignored)
  #expect(apply(deleted, .manualStartFailed(id)).disposition == .ignored)
}

func startingManualSession() throws -> Session {
  let session = apply(Session(), .startManual(replacing: false)).session
  try #require(session.phase == .startingManual)
  return session
}
func manualStartErrorSession() throws -> Session {
  let session = try startingManualSession()
  return apply(session, .manualStartFailed(try #require(session.pendingManualStart))).session
}

@Test("V09: all phases define explicit manual-start acknowledgement, failure and retry outcomes")
func manualStartTransitionMatrix() throws {
  let editing = try editor()
  var invalid = Facelets.solved.faces
  invalid[0] = .right
  let solving = try solvingSession()
  let preparing = try preparingSession()
  let guide = try durableGuide()
  let saving = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let failure = apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
  let draftSaving = try draftSavingSession()
  let draftError = apply(
    draftSaving, .draftPersistFailed(try #require(draftSaving.pendingDraftSave).id)
  ).session
  let deleting = try deletingSession()
  let deletionError = apply(deleting, .deletionFailed(try #require(deleting.pendingDeletion)))
    .session
  let rows: [(Session, String)] = [
    (Session(), "IIR"), (editing, "IIR"),
    (apply(editing, .validate(try Facelets(invalid))).session, "IIR"),
    (apply(editing, .validate(.solved)).session, "IIR"),
    (try offeredSession(), "IIR"), (solving, "IIR"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "IIR"),
    (preparing, "IIR"), (apply(preparing, .background).session, "IIR"),
    (guide, "IIR"), (saving, "IIR"), (failure, "IIR"),
    (try finishedGuide(), "IIR"), (apply(failure, .compare(.uncertain)).session, "IIR"),
    (draftSaving, "IIR"), (draftError, "IIR"), (deleting, "IIR"), (deletionError, "IIR"),
    (try startingManualSession(), "AAR"), (try manualStartErrorSession(), "IIA"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (state, codes) in rows {
    let id = state.pendingManualStart ?? SaveID(revision: state.revision, sequence: .max)
    let events: [SessionEvent] = [.manualStarted(id), .manualStartFailed(id), .retryManualStart]
    for (event, code) in zip(events, codes) {
      let result = apply(state, event)
      let expected: EventDisposition =
        code == "A" ? .accepted : code == "I" ? .ignored : .rejected(.unavailableEvent)
      #expect(result.disposition == expected)
      if code != "A" { #expect(result.session == state && result.commands.isEmpty) }
    }
  }
}

@Test("V11: manual boundary validates revisions and preserves corrupt or unsupported data")
func manualStartArchiveGuards() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  #expect(throws: ArchiveError.invalidProgress) { try ManualStartArchive.encode(revision: 0) }
  let valid = try ManualStartArchive.encode(revision: 4)
  #expect(try ManualStartArchive.decode(valid) == 4)
  #expect(throws: ArchiveError.sizeLimit) {
    try ManualStartArchive.decode(Data(repeating: 0, count: GuideArchive.maximumBytes + 1))
  }
  let draft = ManualDraft(palette: try archivePalette(), revision: 4)
  try await store.saveDraft(draft, lease: store.currentLease())
  for stale in [UInt64(0), 3, 4] {
    await #expect(throws: SessionStoreError.staleWrite) {
      try await store.startManual(revision: stale, lease: store.currentLease())
    }
  }
  #expect(try await store.restore().session.draft == draft)
  try await store.startManual(revision: 5, lease: store.currentLease())
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.saveDraft(draft, lease: store.currentLease())
  }
  let path = directory.appendingPathComponent("manual-start.json")
  for broken in [Data("bad".utf8), Data("{\"schema\":99}".utf8)] {
    try broken.write(to: path)
    await #expect(throws: (any Error).self) { try await store.restore() }
    await #expect(throws: (any Error).self) {
      try await store.startManual(revision: 6, lease: store.currentLease())
    }
    await #expect(throws: (any Error).self) {
      try await store.saveDraft(
        ManualDraft(palette: archivePalette(), revision: 6), lease: store.currentLease())
    }
    #expect(try Data(contentsOf: path) == broken)
  }
  _ = try await store.delete(lease: store.currentLease())
  #expect(!FileManager.default.fileExists(atPath: path.path))
}

@Test("V11: identical start retries re-enter durable replacement and never roll back newer input")
func manualStartRetryWriteFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  try await store.startManual(revision: 1, lease: store.currentLease())
  let draft = ManualDraft(palette: try archivePalette(), revision: 2)
  try await store.saveDraft(draft, lease: store.currentLease())
  let failing = SessionStore(directory: directory) { stage in
    if stage == .beforeWrite { throw ManualStartFailure.stopped }
  }
  // Seeing the marker is not proof a previously reported directory-sync failure was resolved.
  await #expect(throws: ManualStartFailure.self) {
    try await failing.startManual(revision: 1, lease: failing.currentLease())
  }
  #expect(try await failing.restore().session.draft == draft)
}

@Test(
  "V09: replacement invalidates outstanding guide callbacks even before the new boundary finishes")
func manualStartRejectsOldGuideCallback() throws {
  let preparing = try preparingSession()
  let oldID = try #require(preparing.pendingSave).id
  let home = apply(apply(preparing, .background).session, .cancel).session
  let starting = apply(home, .startManual(replacing: true)).session
  #expect(starting.phase == .startingManual && starting.pendingSave == nil)
  for event in [SessionEvent.persisted(oldID), .persistFailed(oldID)] {
    let result = apply(starting, event)
    #expect(result.disposition == .ignored && result.session == starting)
  }
  let zero = try CheckedArchive.encode(["revision": 0])
  #expect(throws: ArchiveError.invalidProgress) { try ManualStartArchive.decode(zero) }
}
