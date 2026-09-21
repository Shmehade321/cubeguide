import CubeCore
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@Test("R10: finishing guidance requests confirmation; matching durable save alone completes it")
func completionConfirmationBarrier() throws {
  let finished = try finishedGuide()
  #expect(finished.phase == .expectedSolved && finished.completion == nil)
  let requested = apply(finished, .confirmCompletion)
  #expect(requested.disposition == .accepted)
  #expect(requested.session.phase == .savingCompletion && requested.session.completion == nil)
  let save = try #require(requested.session.pendingSave)
  #expect(save.kind == .completion(.userConfirmed))
  #expect(save.progress.isComplete && !save.pendingPrepared)
  #expect(apply(requested.session, .confirmCompletion).disposition == .ignored)
  let stale = SaveID(revision: save.id.revision, sequence: save.id.sequence + 1)
  #expect(apply(requested.session, .persisted(stale)).disposition == .ignored)
  let complete = apply(requested.session, .persisted(save.id)).session
  #expect(complete.phase == .completed && complete.completion == .userConfirmed)
  #expect(apply(complete, .confirmCompletion).disposition == .ignored)
  let home = apply(complete, .cancel).session
  #expect(home.phase == .home)
  #expect(apply(home, .resume).session.phase == .completed)
}

@Test("R05/R10: solved entered colors complete distinctly without invoking a solver")
func enteredColorsCompletion() throws {
  let solved = apply(try editor(), .validate(.solved)).session
  let requested = apply(solved, .confirmCompletion)
  #expect(requested.disposition == .accepted && requested.session.phase == .savingCompletion)
  let save = try #require(requested.session.pendingSave)
  #expect(save.kind == .completion(.enteredColorsSolved))
  #expect(save.progress.plan.original == .solved && save.progress.plan.moves.isEmpty)
  #expect(requested.commands.count == 1)
  guard case .saveGuide = requested.commands.first else {
    Issue.record("Already-solved input must persist completion without a solve job")
    return
  }
  let completed = apply(requested.session, .persisted(save.id)).session
  #expect(completed.phase == .completed && completed.completion == .enteredColorsSolved)
}

@Test("R10: a complete six-face camera review records scan verification distinctly")
func scanVerifiedCompletion() throws {
  let finished = try Session(rebasingCompleted: finishedGuide(), to: 100)
  let requested = apply(finished, .confirmScanVerified)
  #expect(requested.disposition == .accepted)
  let save = try #require(requested.session.pendingSave)
  #expect(save.id.revision == 100 && save.kind == .completion(.scanVerified))
  let bytes = try GuideArchive.encode(save, palette: archivePalette())
  #expect(try GuideArchive.decode(bytes).completion == .scanVerified)
}

@Test("V11: completion save failures retain confirmation intent and retry with a new identity")
func completionFailureAndInterruption() throws {
  for initial in [try finishedGuide(), apply(try editor(), .validate(.solved)).session] {
    let saving = apply(initial, .confirmCompletion).session
    let id = try #require(saving.pendingSave).id
    let failed = apply(saving, .persistFailed(id)).session
    #expect(failed.phase == .completionStorageError && failed.completion == nil)
    let retry = apply(failed, .retryCompletionSave).session
    let nextID = try #require(retry.pendingSave).id
    #expect(nextID.revision == id.revision && nextID.sequence > id.sequence)
    #expect(apply(retry, .persisted(id)).disposition == .ignored)
    #expect(apply(retry, .background).disposition == .ignored)
    let exiting = apply(retry, .cancel).session
    #expect(exiting.phase == .savingCompletion)
    let home = apply(exiting, .persisted(nextID)).session
    #expect(home.phase == .home && home.completion != nil)
    #expect(apply(home, .resume).session.phase == .completed)
    let deleting = apply(saving, .deleteLocalData(confirmed: true)).session
    #expect(apply(deleting, .persisted(id)).disposition == .ignored)
    #expect(apply(deleting, .persistFailed(id)).disposition == .ignored)
  }
}

@Test(
  "V11/R10: archives retain completion evidence and legacy final progress still requires confirmation"
)
func completionArchiveRoundTrip() throws {
  for original in [try finishedGuide(), apply(try editor(), .validate(.solved)).session] {
    let request = try #require(apply(original, .confirmCompletion).session.pendingSave)
    let bytes = try GuideArchive.encode(request, palette: archivePalette())
    let restored = try GuideArchive.decode(bytes)
    #expect(restored.completion == request.kind.completion)
    #expect(try Session(restoring: restored).phase == .completed)
    let legacy = try mutatedArchive(bytes, payload: { $0.removeValue(forKey: "completion") })
    let unconfirmed = try Session(restoring: GuideArchive.decode(legacy))
    #expect(unconfirmed.phase == .expectedSolved && unconfirmed.completion == nil)
    let reconfirmed = try #require(apply(unconfirmed, .confirmCompletion).session.pendingSave)
    #expect(reconfirmed.kind == request.kind)
    _ = try GuideArchive.encode(reconfirmed, palette: archivePalette())
  }
}

@Test("R10/V11: completion metadata cannot claim success before the guide ends or mislabel input")
func completionArchiveGuards() throws {
  let incomplete = try #require(try preparingSession().pendingSave)
  let forged = GuideSaveRequest(
    id: incomplete.id, kind: .completion(.userConfirmed),
    progress: incomplete.progress, pendingPrepared: false)
  #expect(throws: ArchiveError.invalidProgress) {
    try GuideArchive.encode(forged, palette: archivePalette())
  }
  let bytes = try GuideArchive.encode(incomplete, palette: archivePalette())
  let premature = try mutatedArchive(bytes, payload: { $0["completion"] = "userConfirmed" })
  #expect(throws: (any Error).self) { try GuideArchive.decode(premature) }
  let completion = try #require(apply(try finishedGuide(), .confirmCompletion).session.pendingSave)
  let completeBytes = try GuideArchive.encode(completion, palette: archivePalette())
  let invalid = try mutatedArchive(completeBytes, payload: {
    $0["completion"] = "enteredColorsSolved"
  })
  #expect(throws: (any Error).self) { try GuideArchive.decode(invalid) }
}

@Test("V11: completion save identity includes evidence kind and survives a real relaunch")
func completionStoreRoundTrip() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let completion = try #require(apply(try finishedGuide(), .confirmCompletion).session.pendingSave)
  try await store.save(completion, palette: archivePalette(), lease: store.currentLease())
  let conflict = GuideSaveRequest(
    id: completion.id, kind: .acknowledgement,
    progress: completion.progress, pendingPrepared: false)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.save(conflict, palette: archivePalette(), lease: store.currentLease())
  }
  let restored = try await SessionStore(directory: directory).restore()
  #expect(restored.session.phase == .completed && restored.session.completion == .userConfirmed)
}

func savingCompletionSession() throws -> Session {
  let result = apply(try finishedGuide(), .confirmCompletion).session
  try #require(result.phase == .savingCompletion)
  return result
}
func completionErrorSession() throws -> Session {
  let saving = try savingCompletionSession()
  return apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
}
func completedSession() throws -> Session {
  let saving = try savingCompletionSession()
  return apply(saving, .persisted(try #require(saving.pendingSave).id)).session
}

@Test("R10: every implemented phase defines completion and retry eligibility")
func completionTransitionMatrix() throws {
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
    (try savingRecoverySession(), "RR"), (try recoveryErrorSession(), "RR"),
    (apply(editing, .validate(try Facelets(invalid))).session, "RR"),
    (apply(editing, .validate(.solved)).session, "AR"),
    (try offeredSession(), "RR"), (solving, "RR"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "RR"),
    (preparing, "RR"), (apply(preparing, .background).session, "RR"),
    (guide, "RR"), (saving, "RR"), (failure, "RR"),
    (try finishedGuide(), "AR"), (try recoverySession(from: failure), "RR"),
    (draftSaving, "RR"), (draftError, "RR"), (deleting, "RR"), (deletionError, "RR"),
    (try startingManualSession(), "RR"), (try manualStartErrorSession(), "RR"),
    (try savingCompletionSession(), "IR"), (try completionErrorSession(), "RA"),
    (try completedSession(), "IR"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (state, codes) in rows {
    for (event, code) in zip([SessionEvent.confirmCompletion, .retryCompletionSave], codes) {
      let result = apply(state, event)
      let expected: EventDisposition =
        code == "A" ? .accepted : code == "I" ? .ignored : .rejected(.unavailableEvent)
      #expect(result.disposition == expected)
      if code != "A" { #expect(result.session == state && result.commands.isEmpty) }
    }
  }
}

private enum CompletionInjectedFailure: Error { case stopped }
@Test("V11: interrupted completion writes preserve either unconfirmed or fully confirmed progress")
func completionWriteBoundaries() async throws {
  let completion = try #require(apply(try finishedGuide(), .confirmCompletion).session.pendingSave)
  let baseline = GuideSaveRequest(
    id: SaveID(revision: completion.id.revision, sequence: completion.id.sequence - 1),
    kind: .acknowledgement, progress: completion.progress, pendingPrepared: false)
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let seed = SessionStore(directory: directory)
    try await seed.save(baseline, palette: archivePalette(), lease: seed.currentLease())
    let failing = SessionStore(directory: directory) { stage in
      if stage == boundary { throw CompletionInjectedFailure.stopped }
    }
    await #expect(throws: CompletionInjectedFailure.self) {
      try await failing.save(completion, palette: archivePalette(), lease: failing.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    let restored = try await reopened.restore().session
    #expect(restored.phase == (boundary == .afterReplace ? .completed : .expectedSolved))
    #expect(restored.completion == (boundary == .afterReplace ? .userConfirmed : nil))
    try await reopened.save(completion, palette: archivePalette(), lease: reopened.currentLease())
    #expect(try await reopened.restore().session.completion == .userConfirmed)
  }
}

@MainActor
@Test(
  "R10/V11: coordinator retains a failed confirmation, retries and restores the recorded evidence")
func controllerCompletionRetry() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let progress = try #require(try finishedGuide().guideProgress)
  let finalTurn = GuideSaveRequest(
    id: SaveID(revision: progress.revision, sequence: 10),
    kind: .acknowledgement, progress: progress, pendingPrepared: false)
  try await real.save(finalTurn, palette: archivePalette(), lease: real.currentLease())
  let controller = SessionController(
    storage: ControlledStorage(real, failGuide: true),
    solver: CubeSolver3.SolverService(), playback: RecordingPlayback())
  await controller.load()
  #expect(controller.session.phase == .expectedSolved && controller.session.completion == nil)
  #expect(controller.send(.confirmCompletion) == .accepted)
  await controller.waitForEffects()
  #expect(
    controller.session.phase == .completionStorageError && controller.session.completion == nil)
  #expect(controller.lastError != nil)
  #expect(try await real.restore().session.completion == .userConfirmed)
  #expect(controller.send(.retryCompletionSave) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .completed && controller.lastError == nil)
  #expect(controller.session.completion == .userConfirmed)
  #expect(controller.send(.cancel) == .accepted)
  #expect(controller.send(.resume) == .accepted)
  #expect(controller.session.phase == .completed)
  controller.send(.deleteLocalData(confirmed: true))
  await controller.waitForEffects()
  #expect(controller.session.completion == nil)
  #expect(try await real.restore().session == Session())
}

@MainActor
@Test(
  "R05/R10: complete manual draft reaches entered-color completion and relaunches with the same label"
)
func controllerEnteredCompletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let draft = try filledDraft(.solved, palette: archivePalette())
  try await store.saveDraft(draft, lease: store.currentLease())
  let controller = SessionController(
    storage: store, solver: CubeSolver3.SolverService(), playback: RecordingPlayback())
  await controller.load()
  #expect(controller.send(.validateDraft) == .accepted)
  #expect(controller.session.phase == .alreadySolved)
  #expect(controller.send(.confirmCompletion) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.completion == .enteredColorsSolved)
  #expect(controller.session.phase == .completed)
  let restored = try await store.restore()
  #expect(
    restored.session.phase == .completed && restored.session.completion == .enteredColorsSolved)
  #expect(restored.palette == draft.palette)
}

@Test("R10/R15: leaving the expected-solved screen preserves the need for physical confirmation")
func unconfirmedCompletionMayLeaveHome() throws {
  let finished = try finishedGuide()
  let leaving = apply(finished, .cancel)
  #expect(leaving.disposition == .accepted)
  #expect(leaving.session.phase == .home)
  #expect(leaving.session.completion == nil)
  #expect(leaving.session.guideProgress == finished.guideProgress)
  let resumed = apply(leaving.session, .resume)
  #expect(resumed.disposition == .accepted)
  #expect(resumed.session.phase == .expectedSolved)
  #expect(resumed.session.completion == nil)
}
