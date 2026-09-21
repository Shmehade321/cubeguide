import CubeCore
import Foundation
import Testing

@testable import CubeSession

func deletingSession() throws -> Session {
  let result = apply(Session(), .deleteLocalData(confirmed: true)).session
  try #require(result.phase == .deleting)
  return result
}

@Test(
  "V15: global deletion requires confirmation and does not claim erasure before matching success")
func deletionBarrier() throws {
  let guide = try durableGuide()
  let playing = apply(guide, .play).session
  let refused = apply(playing, .deleteLocalData(confirmed: false))
  #expect(refused.disposition == .rejected(.confirmationRequired))
  #expect(refused.session == playing && refused.commands.isEmpty)
  let transition = apply(playing, .deleteLocalData(confirmed: true))
  let deleting = transition.session
  #expect(deleting.phase == .deleting)
  #expect(deleting.hasWork)
  #expect(deleting.guideProgress == guide.guideProgress)
  #expect(deleting.preview == .idle && deleting.playbackID == nil && !deleting.aligned)
  let id = try #require(deleting.pendingDeletion)
  var sawStop = false
  var sawCancel = false
  var sawDelete = false
  for command in transition.commands {
    switch command {
    case .stopPreview: sawStop = true
    case .cancelSolve: sawCancel = true
    case .deleteLocalData(let commandID): sawDelete = commandID == id
    default: Issue.record("Unexpected deletion command")
    }
  }
  #expect(sawStop && sawCancel && sawDelete)
  #expect(apply(deleting, .deleteLocalData(confirmed: true)).disposition == .ignored)
  #expect(apply(deleting, .deleted(DeletionID())).disposition == .ignored)
  let home = apply(deleting, .deleted(id)).session
  #expect(home.phase == .home && !home.hasWork)
  #expect(home.guideProgress == nil && home.draft == nil && home.confirmedCube == nil)
  #expect(home.pendingDeletion == nil)
  #expect(home.revision > guide.revision)
  #expect(apply(home, .startManual(replacing: false)).session.phase == .startingManual)
}

@Test("V15: failed deletion stays visible; retries and late callbacks cannot reset a newer attempt")
func deletionFailureAndRetry() throws {
  let deleting = try deletingSession()
  let id = try #require(deleting.pendingDeletion)
  let failed = apply(deleting, .deletionFailed(id)).session
  #expect(failed.phase == .deletionError)
  #expect(failed.pendingDeletion == nil)
  #expect(apply(failed, .cancel).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .retryDeletion).session
  #expect(retry.phase == .deleting)
  let retryID = try #require(retry.pendingDeletion)
  #expect(retryID != id)
  #expect(apply(retry, .deleted(id)).disposition == .ignored)
  #expect(apply(retry, .deletionFailed(id)).disposition == .ignored)
  #expect(apply(retry, .deleted(retryID)).session.phase == .home)
}

@Test(
  "V15: deletion invalidates outstanding draft and guide callbacks before filesystem completion")
func deletionRejectsLateProducers() throws {
  let draft = try draftSavingSession()
  let draftID = try #require(draft.pendingDraftSave).id
  let deletingDraft = apply(draft, .deleteLocalData(confirmed: true)).session
  #expect(deletingDraft.pendingDraftSave == nil)
  #expect(apply(deletingDraft, .draftPersisted(draftID)).disposition == .ignored)
  #expect(apply(deletingDraft, .draftPersistFailed(draftID)).disposition == .ignored)
  let guide = try preparingSession()
  let guideID = try #require(guide.pendingSave).id
  let deletingGuide = apply(guide, .deleteLocalData(confirmed: true)).session
  #expect(deletingGuide.pendingSave == nil)
  #expect(apply(deletingGuide, .persisted(guideID)).disposition == .ignored)
  #expect(apply(deletingGuide, .persistFailed(guideID)).disposition == .ignored)
}

@Test("V15: deletion events have explicit outcomes in every implemented workflow phase")
func deletionEventMatrix() throws {
  let editing = try editor()
  var bad = Facelets.solved.faces
  bad[0] = .right
  let solving = try solvingSession()
  let preparing = try preparingSession()
  let guide = try durableGuide()
  let saving = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let storageError = apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
  let draftSaving = try draftSavingSession()
  let draftError = apply(
    draftSaving, .draftPersistFailed(try #require(draftSaving.pendingDraftSave).id)
  ).session
  let deleting = try deletingSession()
  let deletionError = apply(deleting, .deletionFailed(try #require(deleting.pendingDeletion)))
    .session
  // Columns: unconfirmed delete, confirmed delete, retry, success, failure.
  let rows: [(Session, String)] = [
    (Session(), "RARII"), (editing, "RARII"),
    (try startingManualSession(), "RARII"), (try manualStartErrorSession(), "RARII"),
    (apply(editing, .validate(try Facelets(bad))).session, "RARII"),
    (apply(editing, .validate(.solved)).session, "RARII"),
    (try offeredSession(), "RARII"), (solving, "RARII"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "RARII"),
    (preparing, "RARII"), (apply(preparing, .background).session, "RARII"),
    (guide, "RARII"), (saving, "RARII"), (storageError, "RARII"),
    (try finishedGuide(), "RARII"), (apply(storageError, .compare(.uncertain)).session, "RARII"),
    (draftSaving, "RARII"), (draftError, "RARII"),
    (deleting, "RIRAA"), (deletionError, "RAAII"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (session, codes) in rows {
    let id = session.pendingDeletion ?? DeletionID()
    let events: [SessionEvent] = [
      .deleteLocalData(confirmed: false), .deleteLocalData(confirmed: true),
      .retryDeletion, .deleted(id), .deletionFailed(id),
    ]
    try #require(events.count == codes.count)
    for (event, code) in zip(events, codes) {
      let result = apply(session, event)
      let actual: Character
      switch result.disposition {
      case .accepted: actual = "A"
      case .ignored: actual = "I"
      case .rejected: actual = "R"
      }
      #expect(actual == code, "\(session.phase) + \(event)")
      if code != "A" { #expect(result.session == session && result.commands.isEmpty) }
    }
  }
}

@Test(
  "V15: real store deletion clears guide/draft and invalidates leases before reducer returns Home")
func deletionFilesystemIntegration() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let lease = await store.currentLease()
  let palette = try archivePalette()
  let draft = ManualDraft(palette: palette)
  try await store.saveDraft(draft, lease: lease)
  let preparing = try preparingSession()
  let guide = try #require(preparing.pendingSave)
  try await store.save(guide, palette: palette, lease: lease)
  let session = apply(preparing, .persisted(guide.id)).session
  let deleting = apply(session, .deleteLocalData(confirmed: true)).session
  let id = try #require(deleting.pendingDeletion)
  #expect(deleting.phase != .home)
  _ = try await store.delete(lease: lease)
  let home = apply(deleting, .deleted(id)).session
  #expect(home.phase == .home && !home.hasWork)
  let reopened = SessionStore(directory: directory)
  #expect(try await reopened.load() == nil)
  #expect(try await reopened.loadDraft() == nil)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.saveDraft(draft, lease: lease)
  }
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.save(guide, palette: palette, lease: lease)
  }
}

@Test(
  "V15: failed deletion blocks old playback and preserves data; deletion works at revision exhaustion"
)
func deletionFailureRetainsContext() throws {
  let guide = try durableGuide()
  let playing = apply(guide, .play).session
  let oldPlayback = try #require(playing.playbackID)
  let deleting = apply(playing, .deleteLocalData(confirmed: true)).session
  let failed = apply(deleting, .deletionFailed(try #require(deleting.pendingDeletion))).session
  #expect(failed.guideProgress == guide.guideProgress && failed.hasWork)
  #expect(apply(failed, .previewFinished(oldPlayback)).disposition == .ignored)
  #expect(apply(failed, .play).disposition == .rejected(.unavailableEvent))
  #expect(
    apply(failed, .acknowledge(try #require(guide.pendingAction).id)).disposition
      == .rejected(.unavailableEvent))
  let exhausted = apply(Session(revision: .max), .deleteLocalData(confirmed: true)).session
  #expect(exhausted.phase == .deleting)
  let cleared = apply(exhausted, .deleted(try #require(exhausted.pendingDeletion))).session
  #expect(cleared.phase == .home && cleared.revision == .max)
  #expect(
    apply(cleared, .startManual(replacing: false)).disposition == .rejected(.revisionExhausted))
}
