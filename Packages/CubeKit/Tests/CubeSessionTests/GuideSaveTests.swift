import CubeCore
import Testing

@testable import CubeSession

func preparingSession() throws -> Session {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  return apply(solving, response(solving, outcome: .verified(plan))).session
}
func durableGuide() throws -> Session {
  let ready = try preparingSession()
  let save = try #require(ready.pendingSave)
  let saved = apply(ready, .persisted(save.id)).session
  try #require(saved.phase == .guide)
  return apply(saved, .confirmAlignment).session
}

@Test("V09: preview requires durable preparation and explicit physical alignment")
func durablePreparationBarrier() throws {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  let transition = apply(solving, response(solving, outcome: .verified(plan)))
  let preparing = transition.session
  #expect(preparing.phase == .preparingAction)
  #expect(!preparing.preparationDurable)
  #expect(apply(preparing, .play).disposition == .rejected(.unavailableEvent))
  let save = try #require(preparing.pendingSave)
  #expect(save.kind == .preparation)
  #expect(save.progress.acknowledgedActions == 0)
  #expect(save.pendingPrepared)
  if case .saveGuide(let command) = transition.commands.first {
    #expect(command == save)
  } else {
    Issue.record("Must persist a concrete pending action before preview")
  }
  let wrong = SaveID(revision: save.id.revision, sequence: save.id.sequence + 1)
  #expect(apply(preparing, .persisted(wrong)).disposition == .ignored)
  let saved = apply(preparing, .persisted(save.id)).session
  #expect(saved.phase == .guide)
  #expect(saved.preparationDurable)
  #expect(!saved.aligned)
  #expect(apply(saved, .play).disposition == .rejected(.unavailableEvent))
  let aligned = apply(saved, .confirmAlignment).session
  #expect(aligned.aligned)
  let playing = apply(aligned, .play).session
  #expect(playing.preview == .playing)
  #expect(playing.guideProgress?.acknowledgedActions == 0)
}

@Test("V09: physical acknowledgement advances only after its matching durable save")
func acknowledgedSaveBarrier() throws {
  let guide = try durableGuide()
  let action = try #require(guide.pendingAction)
  let saving = apply(guide, .acknowledge(action.id))
  #expect(saving.session.phase == .savingAcknowledgement)
  #expect(saving.session.guideProgress?.acknowledgedActions == 0)
  #expect(saving.session.pendingAction == action)
  let save = try #require(saving.session.pendingSave)
  #expect(save.kind == .acknowledgement)
  #expect(save.progress.acknowledgedActions == 1)
  #expect(!save.pendingPrepared)
  #expect(apply(saving.session, .acknowledge(action.id)).disposition == .ignored)
  let persisted = apply(saving.session, .persisted(save.id))
  #expect(persisted.session.guideProgress?.acknowledgedActions == 1)
  #expect(persisted.session.guideProgress?.moveIndex == 0)
  #expect(persisted.session.phase == .preparingAction)
  #expect(!persisted.session.preparationDurable)
  let preparation = try #require(persisted.session.pendingSave)
  #expect(preparation.id != save.id)
  #expect(preparation.progress.pending?.id.actionIndex == 1)
  #expect(apply(persisted.session, .persisted(save.id)).disposition == .ignored)
  let next = apply(persisted.session, .persisted(preparation.id)).session
  #expect(next.phase == .guide)
  #expect(next.pendingAction?.id.actionIndex == 1)
  #expect(apply(next, .acknowledge(action.id)).disposition == .ignored)
  let turn = try #require(next.pendingAction)
  let last = apply(next, .acknowledge(turn.id)).session
  let finalSave = try #require(last.pendingSave)
  let finished = apply(last, .persisted(finalSave.id)).session
  #expect(finished.phase == .expectedSolved)
  #expect(finished.guideProgress?.state == .solved)
  #expect(finished.guideProgress?.moveIndex == 1)
  #expect(finished.pendingAction == nil)
}

@Test(
  "V09: animation, pause and replay cannot acknowledge a move or accept stale playback completion")
func playbackCannotAdvance() throws {
  let guide = try durableGuide()
  let action = try #require(guide.pendingAction)
  let playing = apply(guide, .play).session
  let oldID = try #require(playing.playbackID)
  #expect(apply(playing, .acknowledge(action.id)).disposition == .rejected(.unavailableEvent))
  let paused = apply(playing, .pause).session
  #expect(paused.preview == .paused)
  #expect(apply(paused, .previewFinished(oldID)).disposition == .ignored)
  let replay = apply(paused, .replay).session
  let newID = try #require(replay.playbackID)
  #expect(newID != oldID)
  #expect(apply(replay, .previewFinished(oldID)).disposition == .ignored)
  let finished = apply(replay, .previewFinished(newID)).session
  #expect(finished.preview == .finished)
  #expect(finished.guideProgress?.acknowledgedActions == 0)
  #expect(finished.pendingAction == action)
}

@Test(
  "V11: failed acknowledgement preserves durable progress and retries only after physical comparison"
)
func failedAcknowledgementRecovery() throws {
  let guide = try durableGuide()
  let action = try #require(guide.pendingAction)
  let saving = apply(guide, .acknowledge(action.id)).session
  let oldSave = try #require(saving.pendingSave)
  let failed = apply(saving, .persistFailed(oldSave.id)).session
  #expect(failed.phase == .storageError)
  #expect(failed.guideProgress?.acknowledgedActions == 0)
  #expect(failed.pendingSave == nil)
  #expect(apply(failed, .play).disposition == .rejected(.unavailableEvent))
  #expect(apply(failed, .acknowledge(action.id)).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .compare(.after)).session
  #expect(retry.phase == .savingAcknowledgement)
  let newSave = try #require(retry.pendingSave)
  #expect(newSave.id != oldSave.id)
  #expect(newSave.progress.acknowledgedActions == 1)
  #expect(retry.guideProgress?.acknowledgedActions == 0)
  #expect(apply(retry, .persisted(oldSave.id)).disposition == .ignored)
  let before = apply(failed, .compare(.before)).session
  #expect(before.phase == .guide)
  #expect(before.guideProgress?.acknowledgedActions == 0)
  #expect(before.aligned)
  let uncertain = apply(failed, .compare(.uncertain)).session
  #expect(uncertain.phase == .recovery)
  #expect(uncertain.guideProgress == guide.guideProgress)
  let kept = apply(uncertain, .cancel).session
  #expect(kept.phase == .resumeCheck)
}

@Test("V11: preparation failure cannot enable preview or acknowledge an unprepared action")
func failedPreparationRecovery() throws {
  let preparing = try preparingSession()
  let request = try #require(preparing.pendingSave)
  let failed = apply(preparing, .persistFailed(request.id)).session
  #expect(failed.phase == .storageError)
  #expect(!failed.preparationDurable)
  #expect(apply(failed, .compare(.after)).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .compare(.before)).session
  #expect(retry.phase == .preparingAction)
  #expect(retry.aligned)
  #expect(retry.pendingSave?.id != request.id)
  #expect(apply(retry, .play).disposition == .rejected(.unavailableEvent))
  let saved = apply(retry, .persisted(try #require(retry.pendingSave).id)).session
  #expect(saved.phase == .guide)
  #expect(apply(saved, .play).session.preview == .playing)
}

@Test(
  "V11: interrupted preparation/acknowledgement settles without restarting preview or losing progress"
)
func interruptedSaves() throws {
  let preparing = try preparingSession()
  let request = try #require(preparing.pendingSave)
  let interrupted = apply(preparing, .background).session
  #expect(interrupted.phase == .resumeCheck)
  #expect(apply(interrupted, .compare(.after)).disposition == .rejected(.unavailableEvent))
  let settled = apply(interrupted, .persisted(request.id)).session
  #expect(settled.phase == .resumeCheck)
  #expect(settled.preparationDurable)
  #expect(!settled.aligned)
  let matched = apply(settled, .compare(.before)).session
  #expect(matched.phase == .guide)
  #expect(matched.aligned)
  let playing = apply(matched, .play).session
  let paused = apply(playing, .background).session
  #expect(paused.phase == .resumeCheck)
  #expect(!paused.aligned)
  #expect(paused.preview == .idle)
  #expect(apply(paused, .previewFinished(try #require(playing.playbackID))).disposition == .ignored)
  let after = apply(paused, .compare(.after)).session
  let ack = try #require(after.pendingSave)
  let hidden = apply(after, .background).session
  #expect(hidden.phase == .savingAcknowledgement)
  let acknowledged = apply(hidden, .persisted(ack.id)).session
  #expect(acknowledged.phase == .resumeCheck)
  #expect(acknowledged.guideProgress?.acknowledgedActions == 1)
  #expect(acknowledged.pendingSave == nil)
  #expect(!acknowledged.preparationDurable)
  let nextPreparation = apply(acknowledged, .compare(.before)).session
  let next = apply(nextPreparation, .persisted(try #require(nextPreparation.pendingSave).id))
    .session
  let lastSave = apply(next, .acknowledge(try #require(next.pendingAction).id)).session
  let hiddenLast = apply(lastSave, .background).session
  let completed = apply(hiddenLast, .persisted(try #require(hiddenLast.pendingSave).id)).session
  #expect(completed.phase == .expectedSolved)
  #expect(completed.guideProgress?.isComplete == true)
}

func finishedGuide() throws -> Session {
  var current = try durableGuide()
  let count = try #require(current.guideProgress).actions.count
  for _ in 0..<count {
    current = apply(current, .acknowledge(try #require(current.pendingAction).id)).session
    current = apply(current, .persisted(try #require(current.pendingSave).id)).session
    if current.phase == .preparingAction {
      current = apply(current, .persisted(try #require(current.pendingSave).id)).session
    }
  }
  try #require(current.phase == .expectedSolved)
  return current
}

@Test("V11: leaving a storage error preserves the pending comparison when resumed")
func storageErrorHome() throws {
  let guide = try durableGuide()
  let saving = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let failed = apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
  let home = apply(failed, .cancel)
  #expect(home.disposition == .accepted)
  #expect(home.session.phase == .home)
  #expect(home.session.guideProgress == guide.guideProgress)
  let resumed = apply(home.session, .resume).session
  #expect(resumed.phase == .resumeCheck)
  #expect(apply(resumed, .compare(.after)).session.phase == .savingAcknowledgement)
}

@Test(
  "V09/V11: save, playback and comparison events have explicit outcomes in every implemented phase")
func persistenceEventMatrix() throws {
  let editing = try editor()
  var bad = Facelets.solved.faces
  bad[0] = .right
  let solving = try solvingSession()
  let preparing = try preparingSession()
  let ready = apply(preparing, .persisted(try #require(preparing.pendingSave).id)).session
  let guide = try durableGuide()
  let playing = apply(guide, .play).session
  let paused = apply(playing, .pause).session
  let finished = apply(playing, .previewFinished(try #require(playing.playbackID))).session
  let saving = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let failed = apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
  let prepFailed = apply(preparing, .persistFailed(try #require(preparing.pendingSave).id)).session
  // Columns: save success, save failure, align, play, pause, replay, playback end,
  // acknowledgement, matches before, matches after, uncertain. A/R/I as in the workflow matrix.
  let draftSaving = try draftSavingSession()
  let draftError = apply(
    draftSaving, .draftPersistFailed(try #require(draftSaving.pendingDraftSave).id)
  ).session
  let deleting = try deletingSession()
  let deletionError = apply(deleting, .deletionFailed(try #require(deleting.pendingDeletion)))
    .session
  let rows: [(Session, String)] = [
    (Session(), "IIRRRRIIRRR"), (editing, "IIRRRRIIRRR"),
    (try savingCompletionSession(), "AARRRRIIRRR"), (try completionErrorSession(), "IIRRRRIIRRR"),
    (try completedSession(), "IIRRRRIIRRR"),
    (try startingManualSession(), "IIRRRRIIRRR"), (try manualStartErrorSession(), "IIRRRRIIRRR"),
    (deleting, "IIRRRRIIRRR"), (deletionError, "IIRRRRIIRRR"),
    (draftSaving, "IIRRRRIIRRR"), (draftError, "IIRRRRIIRRR"),
    (apply(editing, .validate(try Facelets(bad))).session, "IIRRRRIIRRR"),
    (apply(editing, .validate(.solved)).session, "IIRRRRIIRRR"),
    (try offeredSession(), "IIRRRRIIRRR"), (solving, "IIRRRRIIRRR"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "IIRRRRIIRRR"),
    (preparing, "AARRRRIIRRR"),
    (apply(preparing, .background).session, "AARRRRIIRRR"),
    (ready, "IIARRRIRRRR"), (guide, "IIIARAIARRR"),
    (playing, "IIRIAAARRRR"), (paused, "IIRARAIRRRR"), (finished, "IIRARAIARRR"),
    (saving, "AARRRRIIRRR"), (failed, "IIRRRRIRAAA"), (prepFailed, "IIRRRRIRARA"),
    (apply(failed, .compare(.uncertain)).session, "IIRRRRIRRRR"),
    (try finishedGuide(), "IIRRRRIIRRR"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (state, codes) in rows {
    let saveID = state.pendingSave?.id ?? SaveID(revision: state.revision, sequence: .max)
    let action =
      try state.pendingAction?.id
      ?? ActionID(sessionRevision: state.revision, moveIndex: 0, actionIndex: 0)
    let playback = state.playbackID ?? PlaybackID(action: action, sequence: .max)
    let events: [SessionEvent] = [
      .persisted(saveID), .persistFailed(saveID), .confirmAlignment,
      .play, .pause, .replay, .previewFinished(playback), .acknowledge(action),
      .compare(.before), .compare(.after), .compare(.uncertain),
    ]
    try #require(events.count == codes.count)
    for (event, code) in zip(events, codes) {
      let result = apply(state, event)
      let expected: EventDisposition =
        code == "A" ? .accepted : code == "I" ? .ignored : .rejected(.unavailableEvent)
      #expect(result.disposition == expected, "\(state.phase) + \(event)")
      if code != "A" {
        #expect(result.session == state)
        #expect(result.commands.isEmpty)
      }
    }
  }
}
