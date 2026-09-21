import CubeCore
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@Test("R10: mismatch stops previews, revokes completion and waits for durable recovery")
func mismatchBarrier() throws {
  let playing = apply(try durableGuide(), .play).session
  for original in [try durableGuide(), playing, try finishedGuide(), try completedSession()] {
    let requested = apply(original, .mismatch)
    #expect(requested.disposition == .accepted)
    #expect(requested.session.phase == .savingRecovery)
    #expect(requested.session.recoveryRequired && requested.session.completion == nil)
    #expect(!requested.session.aligned && requested.session.preview == .idle)
    #expect(requested.session.guideProgress == original.guideProgress)
    if let playback = original.playbackID {
      #expect(apply(requested.session, .previewFinished(playback)).disposition == .ignored)
    }
    let save = try #require(requested.session.pendingSave)
    #expect(save.kind == .recovery)
    #expect(
      requested.commands.contains {
        if case .stopPreview = $0 { return true }
        return false
      })
    #expect(apply(requested.session, .mismatch).disposition == .ignored)
    #expect(apply(requested.session, .play).disposition == .rejected(.unavailableEvent))
    let recovered = apply(requested.session, .persisted(save.id)).session
    #expect(recovered.phase == .recovery && recovered.recoveryRequired)
    let cancelled = apply(recovered, .cancel).session
    #expect(
      cancelled.phase
        == (original.guideProgress?.isComplete == true ? .expectedSolved : .resumeCheck))
    #expect(cancelled.completion == nil && cancelled.guideProgress == original.guideProgress)
  }
}

@Test("R10/V11: uncertain comparison is durable and retry cannot advance a physical action")
func uncertainRecoveryRetry() throws {
  let before = apply(try durableGuide(), .background).session
  let saving = apply(before, .compare(.uncertain)).session
  #expect(saving.phase == .savingRecovery)
  let id = try #require(saving.pendingSave).id
  let failed = apply(saving, .persistFailed(id)).session
  #expect(failed.phase == .recoveryStorageError && failed.recoveryRequired)
  #expect(apply(failed, .compare(.after)).disposition == .rejected(.unavailableEvent))
  #expect(apply(failed, .confirmCompletion).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .retryRecoverySave).session
  let next = try #require(retry.pendingSave)
  #expect(next.id != id && next.progress == before.guideProgress)
  #expect(apply(retry, .persisted(id)).disposition == .ignored)
  #expect(apply(retry, .background).disposition == .ignored)
  let recovery = apply(retry, .persisted(next.id)).session
  let comparison = apply(recovery, .cancel).session
  let preparing = apply(comparison, .compare(.before)).session
  #expect(preparing.phase == .preparingAction && preparing.recoveryRequired)
  let prep = try #require(preparing.pendingSave)
  let guide = apply(preparing, .persisted(prep.id)).session
  #expect(guide.phase == .guide && !guide.recoveryRequired)
  #expect(guide.guideProgress?.acknowledgedActions == before.guideProgress?.acknowledgedActions)
}

@Test("V11/R10: recovery metadata survives relaunch and cannot coexist with completion")
func recoveryArchiveRoundTrip() throws {
  for initial in [try durableGuide(), try completedSession()] {
    let request = try #require(apply(initial, .mismatch).session.pendingSave)
    let bytes = try GuideArchive.encode(request, palette: archivePalette())
    let restored = try GuideArchive.decode(bytes)
    #expect(restored.recoveryRequired && restored.completion == nil)
    #expect(try Session(restoring: restored).phase == .recovery)
    #expect(restored.pendingPrepared == initial.preparationDurable)
    let legacy = try mutatedArchive(bytes, payload: { $0.removeValue(forKey: "recoveryRequired") })
    #expect(try !GuideArchive.decode(legacy).recoveryRequired)
  }
  let completion = try #require(apply(try finishedGuide(), .confirmCompletion).session.pendingSave)
  let bytes = try GuideArchive.encode(completion, palette: archivePalette())
  let conflicting = try mutatedArchive(bytes, payload: { $0["recoveryRequired"] = true })
  #expect(throws: ArchiveError.invalidProgress) { try GuideArchive.decode(conflicting) }
}

@Test("V11: a recovery save cannot be silently replaced using the same identity")
func recoveryStoreIdentity() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let request = try #require(apply(try durableGuide(), .mismatch).session.pendingSave)
  try await store.save(request, palette: archivePalette(), lease: store.currentLease())
  let conflicting = GuideSaveRequest(
    id: request.id, kind: .preparation, progress: request.progress, pendingPrepared: true)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.save(conflicting, palette: archivePalette(), lease: store.currentLease())
  }
  #expect(try await store.restore().session.phase == .recovery)
}

func savingRecoverySession() throws -> Session {
  let result = apply(try durableGuide(), .mismatch).session
  try #require(result.phase == .savingRecovery)
  return result
}
func recoveryErrorSession() throws -> Session {
  let saving = try savingRecoverySession()
  return apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
}
func recoverySession(from state: Session) throws -> Session {
  let saving = apply(state, .compare(.uncertain)).session
  let id = try #require(saving.pendingSave).id
  return apply(saving, .persisted(id)).session
}

@Test("R10: cancelling recovery preserves the old plan; manual replacement needs explicit consent")
func recoveryManualReplacement() throws {
  let saving = try savingRecoverySession()
  let recovery = apply(saving, .persisted(try #require(saving.pendingSave).id)).session
  #expect(
    apply(recovery, .startManual(replacing: false)).disposition == .rejected(.replacementRequired))
  let replacing = apply(recovery, .startManual(replacing: true)).session
  #expect(replacing.phase == .startingManual && replacing.plan == recovery.plan)
  #expect(replacing.revision > recovery.revision)
  let new = apply(replacing, .manualStarted(try #require(replacing.pendingManualStart))).session
  #expect(new.phase == .editing && new.plan == nil && !new.recoveryRequired)
  let exiting = apply(saving, .cancel).session
  #expect(exiting.phase == .savingRecovery)
  let comparison = apply(exiting, .persisted(try #require(exiting.pendingSave).id)).session
  #expect(comparison.phase == .resumeCheck && comparison.recoveryRequired)
  let deleting = apply(saving, .deleteLocalData(confirmed: true)).session
  #expect(apply(deleting, .persisted(try #require(saving.pendingSave).id)).disposition == .ignored)
}

@Test("R10: mismatch and recovery retry have explicit outcomes in every workflow phase")
func recoveryTransitionMatrix() throws {
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
    (Session(), "RR"), (editing, "RR"),
    (apply(editing, .validate(try Facelets(invalid))).session, "RR"),
    (apply(editing, .validate(.solved)).session, "RR"),
    (try offeredSession(), "RR"), (solving, "RR"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "RR"),
    (preparing, "RR"), (apply(preparing, .background).session, "RR"),
    (guide, "AR"), (saving, "RR"), (failure, "RR"),
    (try finishedGuide(), "AR"), (try recoverySession(from: failure), "IR"),
    (draftSaving, "RR"), (draftError, "RR"), (deleting, "RR"), (deletionError, "RR"),
    (try startingManualSession(), "RR"), (try manualStartErrorSession(), "RR"),
    (try savingCompletionSession(), "RR"), (try completionErrorSession(), "RR"),
    (try completedSession(), "AR"), (try savingRecoverySession(), "IR"),
    (try recoveryErrorSession(), "RA"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (state, codes) in rows {
    for (event, code) in zip([SessionEvent.mismatch, .retryRecoverySave], codes) {
      let result = apply(state, event)
      let expected: EventDisposition =
        code == "A" ? .accepted : code == "I" ? .ignored : .rejected(.unavailableEvent)
      #expect(result.disposition == expected)
      if code != "A" { #expect(result.session == state && result.commands.isEmpty) }
    }
  }
}

private enum RecoveryWriteFailure: Error { case stopped }
@Test("V11: failed recovery writes leave a complete prior confirmation or complete recovery record")
func recoveryWriteBoundaries() async throws {
  let finishing = apply(try finishedGuide(), .confirmCompletion).session
  let confirmation = try #require(finishing.pendingSave)
  let completed = apply(finishing, .persisted(confirmation.id)).session
  let recovery = try #require(apply(completed, .mismatch).session.pendingSave)
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let seed = SessionStore(directory: directory)
    try await seed.save(confirmation, palette: archivePalette(), lease: seed.currentLease())
    let failing = SessionStore(directory: directory) { stage in
      if stage == boundary { throw RecoveryWriteFailure.stopped }
    }
    await #expect(throws: RecoveryWriteFailure.self) {
      try await failing.save(recovery, palette: archivePalette(), lease: failing.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    let state = try await reopened.restore().session
    #expect(state.phase == (boundary == .afterReplace ? .recovery : .completed))
    #expect(state.completion == (boundary == .afterReplace ? nil : .userConfirmed))
    try await reopened.save(recovery, palette: archivePalette(), lease: reopened.currentLease())
    #expect(try await reopened.restore().session.phase == .recovery)
  }
}

@MainActor
@Test(
  "R10/V11: coordinator retries recovery and clears it only after a new durable comparison or confirmation"
)
func controllerRecoveryLifecycle() async throws {
  for completed in [false, true] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    let seed =
      try completed
      ? #require(apply(try finishedGuide(), .confirmCompletion).session.pendingSave)
      : #require(try preparingSession().pendingSave)
    try await store.save(seed, palette: archivePalette(), lease: store.currentLease())
    let controller = SessionController(
      storage: ControlledStorage(store, failGuide: true),
      solver: CubeSolver3.SolverService(), playback: RecordingPlayback())
    await controller.load()
    if !completed { controller.send(.compare(.before)) }
    #expect(controller.send(.mismatch) == .accepted)
    #expect(controller.session.completion == nil)
    await controller.waitForEffects()
    #expect(controller.session.phase == .recoveryStorageError && controller.lastError != nil)
    #expect(try await store.restore().session.phase == .recovery)
    controller.send(.retryRecoverySave)
    await controller.waitForEffects()
    #expect(controller.session.phase == .recovery && controller.lastError == nil)
    controller.send(.cancel)
    #expect(controller.send(completed ? .confirmCompletion : .compare(.before)) == .accepted)
    await controller.waitForEffects()
    #expect(controller.session.phase == (completed ? .completed : .guide))
    #expect(!controller.session.recoveryRequired)
    #expect(try await !store.restore().session.recoveryRequired)
  }
}

@MainActor @Test("R10: confirmed manual recovery retires the old guide in real storage")
func controllerManualRecovery() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let save = try #require(apply(try durableGuide(), .mismatch).session.pendingSave)
  try await store.save(save, palette: archivePalette(), lease: store.currentLease())
  let controller = SessionController(
    storage: store, solver: CubeSolver3.SolverService(), playback: RecordingPlayback())
  await controller.load()
  #expect(controller.session.phase == .recovery)
  #expect(controller.send(.startManual(replacing: false)) == .rejected(.replacementRequired))
  #expect(controller.send(.startManual(replacing: true)) == .accepted)
  await controller.waitForEffects()
  #expect(
    controller.session.phase == .editing && controller.session.plan == nil
      && controller.palette == nil)
  let reopened = try await store.restore().session
  #expect(reopened.phase == .editing && !reopened.recoveryRequired && reopened.plan == nil)
}
