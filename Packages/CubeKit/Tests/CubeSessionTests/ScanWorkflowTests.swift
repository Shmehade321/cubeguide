import CubeCore
import CubeScan
import Foundation
import Testing

@testable import CubeSession

private func step(_ state: ScanWorkflow, _ event: ScanEvent) -> ScanTransition {
  ScanReducer.reduce(state, event: event)
}
private func observation(_ slot: Face, seed: Double = 0) throws -> ScanFace {
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  let colors: [CubeColor] = [.green, .white, .orange, .blue, .yellow, .red]
  let base = try #require(pendingScan().draft.faces[2])
  let original = base.metadata
  let metadata = try CaptureMetadata(
    width: original.width, height: original.height,
    sourceOrientation: original.sourceOrientation, sourceMirrored: original.sourceMirrored,
    corners: original.corners, pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]),
    samplingVersion: original.samplingVersion)
  let samples = try (0..<9).map {
    try ColorMeasurement(
      median: LabColor(lightness: seed + Double($0), a: 10, b: 20),
      display: base.measurements[0].display, spread: 1, sampleCount: 1600)
  }
  return try ScanFace(
    slot: slot, measurements: samples, metadata: metadata,
    centerName: colors[Int(slot.rawValue)])
}
private func newScan() throws -> ScanWorkflow {
  try ScanWorkflow(starting: PendingScan(draft: ScanDraft(revision: 10), purpose: .newCube))
}
private func scanning() throws -> ScanWorkflow {
  let saving = step(try newScan(), .begin).workflow
  return step(saving, .saved(try #require(saving.pendingSave).id)).workflow
}
private func reviewing(_ state: ScanWorkflow) throws -> ScanWorkflow {
  let frozen = step(state, .capture).workflow
  return step(
    frozen, .captured(try #require(frozen.captureID), try observation(#require(frozen.target)))
  ).workflow
}
private func completeScan() throws -> ScanWorkflow {
  var state = try scanning()
  for _ in 0..<6 {
    state = step(try reviewing(state), .accept).workflow
    state = step(state, .saved(try #require(state.pendingSave).id)).workflow
  }
  try #require(state.phase == .editing)
  return state
}
private func staleID() -> ScanOperationID {
  ScanOperationID(workflow: UUID(), revision: 0, sequence: 0)
}

@Test("R02/R18: capture starts only after the empty scan context is durably saved")
func scanWorkflowStart() throws {
  let initial = try newScan()
  let transition = step(initial, .begin)
  #expect(transition.disposition == .accepted)
  #expect(transition.workflow.phase == .saving && transition.workflow.durable == nil)
  let request = try #require(transition.workflow.pendingSave)
  #expect(request.scan.draft.revision == 10 && request.scan.draft.acceptedCount == 0)
  #expect(transition.commands == [.save(request)])
  #expect(step(transition.workflow, .saved(staleID())).disposition == .ignored)
  #expect(step(transition.workflow, .capture).disposition == .rejected(.unavailableEvent))
  let saved = step(transition.workflow, .saved(request.id))
  #expect(saved.workflow.phase == .scanning && saved.workflow.durable == request.scan)
  #expect(saved.commands == [.startCapture(.front)])
  #expect(step(saved.workflow, .saved(request.id)).disposition == .ignored)
  #expect(throws: ArchiveError.invalidProgress) { try ScanWorkflow(starting: pendingScan()) }
}

@Test(
  "R02/R18: capture, review and accepted-save are separate; six durable faces reach review, not completion"
)
func scanWorkflowSixFaces() throws {
  var state = try scanning()
  for (index, slot) in ScanDraft.captureOrder.enumerated() {
    let freeze = step(state, .capture)
    let id = try #require(freeze.workflow.captureID)
    #expect(freeze.workflow.phase == .freezing)
    #expect(freeze.commands == [.freeze(id, slot)])
    #expect(step(freeze.workflow, .capture).disposition == .ignored)
    let review = step(freeze.workflow, .captured(id, try observation(slot)))
    #expect(review.workflow.phase == .faceReview && review.workflow.review?.slot == slot)
    #expect(review.commands == [.stopCapture])
    #expect(review.workflow.durable?.draft.acceptedCount == index)
    let accepted = step(review.workflow, .accept)
    let save = try #require(accepted.workflow.pendingSave)
    #expect(accepted.workflow.phase == .saving && accepted.workflow.review == nil)
    #expect(accepted.workflow.durable?.draft.acceptedCount == index)
    #expect(save.scan.draft.acceptedCount == index + 1)
    #expect(accepted.commands == [.discardFrame, .save(save)])
    #expect(step(accepted.workflow, .accept).disposition == .ignored)
    let saved = step(accepted.workflow, .saved(save.id))
    state = saved.workflow
    #expect(state.durable?.draft.acceptedCount == index + 1)
    if index == 5 {
      #expect(state.phase == .editing && state.target == nil && saved.commands.isEmpty)
    } else {
      #expect(state.phase == .scanning && state.target == ScanDraft.captureOrder[index + 1])
      #expect(saved.commands == [.startCapture(ScanDraft.captureOrder[index + 1])])
    }
  }
  #expect(
    state.durable?.draft.confirmedCenters?.colors == [
      .green, .white, .orange, .blue, .yellow, .red,
    ])
}

@Test(
  "R03: unaccepted review corrections rotate measurements with overrides and do not touch durable faces"
)
func scanWorkflowReviewEdits() throws {
  let base = try reviewing(scanning())
  let edited = step(base, .editReview(.sticker(row: 0, column: 1, color: .blue)))
  #expect(edited.disposition == .accepted && edited.commands.isEmpty)
  let rotated = step(edited.workflow, .editReview(.rotate(.clockwise))).workflow
  #expect(rotated.review?.measurements.map(\.median.lightness) == [6, 3, 0, 7, 4, 1, 8, 5, 2])
  #expect(rotated.review?.manualOverrides[5] == .blue && rotated.review?.correctionTurns == 1)
  #expect(rotated.durable == base.durable)
  #expect(step(rotated, .editReview(.center(.green))).workflow.review?.centerName == .green)
  #expect(
    step(rotated, .editReview(.sticker(row: 1, column: 1, color: .red))).disposition
      == .rejected(.observation(.centerRequiresAssignment)))
  #expect(
    step(rotated, .editReview(.sticker(row: Int.max, column: 0, color: .red))).disposition
      == .rejected(.observation(.invalidCell)))
  let retake = step(rotated, .retake)
  #expect(retake.workflow.phase == .scanning && retake.workflow.review == nil)
  #expect(retake.workflow.durable == base.durable)
  #expect(retake.commands == [.discardFrame, .startCapture(.front)])
  let partial = ScanWorkflow(restoring: try pendingScan())
  let right = try reviewing(step(partial, .resume(confirmedUnchanged: true)).workflow)
  let duplicate = step(right, .editReview(.center(.orange))).workflow
  let rejected = step(duplicate, .accept)
  #expect(rejected.disposition == .rejected(.observation(.duplicateCenter)))
  #expect(rejected.workflow == duplicate && rejected.commands.isEmpty)
}

@Test("R02/R03: crop reprocessing replaces only the observation and preserves review edits")
func scanWorkflowReviewObservationUpdate() throws {
  let base = try reviewing(scanning())
  let centered = step(base, .editReview(.center(.green))).workflow
  let edited = step(centered, .editReview(.sticker(row: 0, column: 0, color: .blue))).workflow
  let rotated = step(edited, .editReview(.rotate(.clockwise))).workflow
  let replacement = try observation(.front, seed: 80)

  let updated = step(rotated, .updateReviewObservation(replacement))

  #expect(updated.disposition == .accepted)
  #expect(updated.workflow.review?.centerName == .green)
  #expect(updated.workflow.review?.manualOverrides == rotated.review?.manualOverrides)
  #expect(updated.workflow.review?.correctionTurns == 1)
  #expect(updated.workflow.review?.measurements[0].median.lightness == 86)
  #expect(updated.workflow.durable == rotated.durable)
  #expect(updated.commands.isEmpty)
  #expect(
    step(rotated, .updateReviewObservation(try observation(.right, seed: 80))).disposition
      == .rejected(.invalidObservation))
}

@Test(
  "R02/R18: interruptions drop unaccepted frames, retain accepted faces and require explicit physical resume"
)
func scanWorkflowInterruptions() throws {
  let restored = ScanWorkflow(restoring: try pendingScan())
  #expect(restored.phase == .pausedCapture && restored.pauseReason == .relaunch)
  let resumed = step(restored, .resume(confirmedUnchanged: true)).workflow
  let freeze = step(resumed, .capture).workflow
  let review = try reviewing(resumed)
  for state in [resumed, freeze, review] {
    for reason in [ScanPauseReason.background, .permissionDenied, .thermal, .orientationChanged] {
      let paused = step(state, .interrupt(reason))
      #expect(paused.workflow.phase == .pausedCapture && paused.workflow.pauseReason == reason)
      #expect(paused.workflow.review == nil && paused.workflow.captureID == nil)
      #expect(paused.workflow.durable == restored.durable)
      #expect(paused.commands == [.stopCapture, .discardFrame])
      #expect(
        step(paused.workflow, .resume(confirmedUnchanged: false)).disposition
          == .rejected(.confirmationRequired))
      let continued = step(paused.workflow, .resume(confirmedUnchanged: true))
      #expect(
        continued.workflow.phase == .scanning && continued.commands == [.startCapture(.right)])
      if let id = state.captureID {
        #expect(
          step(continued.workflow, .captured(id, try observation(.right))).disposition == .ignored)
      }
    }
    let exit = step(state, .cancel)
    #expect(exit.workflow.phase == .home && exit.workflow.durable == restored.durable)
    #expect(exit.workflow.review == nil && exit.workflow.captureID == nil)
    #expect(exit.commands == [.stopCapture, .discardFrame])
    #expect(step(exit.workflow, .open).workflow.phase == .pausedCapture)
  }
}

@Test(
  "R02: wrong-slot and failed captures pause without damaging accepted observations; stale runs cannot deliver frames"
)
func scanWorkflowCaptureFailures() throws {
  let base = try scanning()
  let freeze = step(base, .capture).workflow
  let id = try #require(freeze.captureID)
  let wrong = step(freeze, .captured(id, try observation(.right)))
  #expect(
    wrong.workflow.phase == .pausedCapture && wrong.workflow.pauseReason == .invalidObservation)
  #expect(wrong.workflow.durable == base.durable && wrong.workflow.review == nil)
  #expect(wrong.commands == [.stopCapture, .discardFrame])
  let failure = step(freeze, .captureFailed(id, .cameraUnavailable))
  #expect(
    failure.workflow.phase == .pausedCapture && failure.workflow.pauseReason == .cameraUnavailable)
  #expect(step(failure.workflow, .captured(id, try observation(.front))).disposition == .ignored)
  let second = step(try scanning(), .capture).workflow
  #expect(second.captureID != id)
  #expect(step(second, .captured(id, try observation(.front))).disposition == .ignored)
  #expect(step(freeze, .captureFailed(staleID(), .captureFailed)).disposition == .ignored)
}

@Test("R18: saves settle after interruption or exit; failures require a fresh identified retry")
func scanWorkflowSaveLifecycle() throws {
  let review = try reviewing(scanning())
  let saving = step(review, .accept).workflow
  let original = try #require(saving.pendingSave)
  let failed = step(saving, .saveFailed(original.id)).workflow
  #expect(failed.phase == .storageError && failed.durable == review.durable)
  #expect(step(failed, .cancel).disposition == .rejected(.unavailableEvent))
  #expect(step(failed, .saved(original.id)).disposition == .ignored)
  let retry = step(failed, .retrySave)
  let request = try #require(retry.workflow.pendingSave)
  #expect(request.id != original.id && request.scan == original.scan)
  #expect(retry.commands == [.save(request)])
  #expect(step(retry.workflow, .saved(original.id)).disposition == .ignored)
  for exit in [false, true] {
    var state = step(retry.workflow, .interrupt(.background)).workflow
    if exit { state = step(state, .cancel).workflow }
    state = step(state, .interrupt(.thermal)).workflow
    #expect(state.phase == .saving && state.durable == review.durable)
    let result = step(state, .saved(request.id))
    #expect(result.workflow.phase == (exit ? .home : .pausedCapture))
    #expect(result.workflow.durable == request.scan && result.commands.isEmpty)
    #expect(result.workflow.pendingSave == nil)
  }
}

@Test("R18: interruption after a failed save still requires a physical check after retry")
func scanWorkflowFailedSaveInterruption() throws {
  let saving = step(try reviewing(scanning()), .accept).workflow
  let first = try #require(saving.pendingSave)
  let failed = step(saving, .saveFailed(first.id)).workflow
  let interrupted = step(failed, .interrupt(.background))
  #expect(interrupted.disposition == .accepted && interrupted.workflow.phase == .storageError)
  #expect(interrupted.commands == [.stopCapture, .discardFrame])
  let retry = step(interrupted.workflow, .retrySave).workflow
  let saved = step(retry, .saved(try #require(retry.pendingSave).id))
  #expect(saved.workflow.phase == .pausedCapture && saved.commands.isEmpty)
  #expect(saved.workflow.durable == first.scan)
  #expect(
    step(saved.workflow, .resume(confirmedUnchanged: false)).disposition
      == .rejected(.confirmationRequired))
}

@Test(
  "R03/R18: complete scan corrections save before review advances; recapture preserves the other five faces"
)
func scanWorkflowCompleteReview() throws {
  let state = try completeScan()
  #expect(ScanWorkflow(restoring: try #require(state.durable)).phase == .editing)
  #expect(step(state, .interrupt(.background)).disposition == .ignored)
  let corrected = step(state, .correct(.back, .sticker(row: 0, column: 0, color: .white)))
  let save = try #require(corrected.workflow.pendingSave)
  #expect(corrected.workflow.durable == state.durable && corrected.workflow.phase == .saving)
  #expect(save.scan.draft.faces[5]?.manualOverrides[0] == .white)
  let saved = step(corrected.workflow, .saved(save.id))
  #expect(saved.workflow.phase == .editing && saved.commands.isEmpty)
  #expect(
    step(state, .correct(.front, .center(.white))).disposition
      == .rejected(.observation(.duplicateCenter)))
  let selected = step(saved.workflow, .recapture(.back)).workflow
  #expect(selected.phase == .pausedCapture && selected.target == .back)
  let resumed = step(selected, .resume(confirmedUnchanged: true)).workflow
  let replacement = step(try reviewing(resumed), .accept).workflow
  let replaced = try #require(replacement.pendingSave)
  #expect(
    replaced.scan.draft.acceptedCount == 6
      && replaced.scan.draft.faces[5]?.manualOverrides[0] == nil)
  for index in 0..<5 { #expect(replaced.scan.draft.faces[index] == save.scan.draft.faces[index]) }
  #expect(step(replacement, .saved(replaced.id)).workflow.phase == .editing)
}

@Test(
  "R18: counter and input-revision exhaustion reject work without wrapping or losing durable input")
func scanWorkflowExhaustion() throws {
  let source = try pendingScan()
  let exhausted = ScanWorkflow(restoring: source, sequence: .max)
  let resumed = step(exhausted, .resume(confirmedUnchanged: true)).workflow
  #expect(step(resumed, .capture).disposition == .rejected(.revisionExhausted))
  let complete = try #require(completeScan().durable)
  let finalSequence = ScanWorkflow(restoring: complete, sequence: .max)
  let blockedSave = step(finalSequence, .correct(.front, .rotate(.half)))
  #expect(blockedSave.disposition == .rejected(.revisionExhausted))
  #expect(blockedSave.workflow == finalSequence && blockedSave.commands.isEmpty)
  let finalDraft = try PendingScan(draft: ScanDraft(revision: .max), purpose: .newCube)
  let last = step(ScanWorkflow(restoring: finalDraft), .resume(confirmedUnchanged: true)).workflow
  let review = try reviewing(last)
  let failure = step(review, .accept)
  #expect(failure.disposition == .rejected(.revisionExhausted))
  #expect(failure.workflow.durable == review.durable && failure.workflow.review == review.review)
}

@Test(
  "V11: reducer save commands persist the retained verification context and relaunch pauses capture"
)
func scanWorkflowRealStorage() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try savingCompletionSession().pendingSave)
  try await store.save(guide, palette: archivePalette(), lease: store.currentLease())
  let pending = try PendingScan(
    draft: ScanDraft(revision: 10), purpose: .verification, retainedGuide: guide.id)
  var state = try ScanWorkflow(starting: pending)
  state = step(state, .begin).workflow
  var request = try #require(state.pendingSave)
  try await store.saveScanDraft(request.scan, lease: store.currentLease())
  state = step(state, .saved(request.id)).workflow
  state = step(try reviewing(state), .accept).workflow
  request = try #require(state.pendingSave)
  try await store.saveScanDraft(request.scan, lease: store.currentLease())
  state = step(state, .saved(request.id)).workflow
  let restored = try await SessionStore(directory: directory).restore()
  #expect(restored.pendingScan == state.durable)
  #expect(
    restored.session.completion == .userConfirmed
      && restored.session.guideProgress == guide.progress)
  let relaunched = ScanWorkflow(restoring: try #require(restored.pendingScan))
  #expect(relaunched.phase == .pausedCapture && relaunched.target == .right)
  #expect(relaunched.review == nil && relaunched.captureID == nil && relaunched.pendingSave == nil)
}

@Test("V09: every scan phase defines all scan-event dispositions explicitly")
func scanWorkflowMatrix() throws {
  let new = try newScan()
  let saving = step(new, .begin).workflow
  let live = try scanning()
  let freeze = step(live, .capture).workflow
  let review = try reviewing(live)
  let failed = step(saving, .saveFailed(try #require(saving.pendingSave).id)).workflow
  let paused = step(live, .interrupt(.background)).workflow
  let home = step(live, .cancel).workflow
  let editing = try completeScan()
  // begin open resume capture captured failure accept retake edit correct recapture saved failed retry interrupt cancel
  let rows: [(ScanWorkflow, String)] = [
    (new, "ARRRIIRRRRRRIIRII"),
    (home, "RARRIIRRRRRRIIRII"),
    (paused, "RRARIIRRRRRRIIRIA"),
    (live, "RRRAIIRRRRRRIIRAA"),
    (freeze, "RRRIAARRRRRRIIRAA"),
    (review, "RRRRIIAAAARRIIRAA"),
    (saving, "RRRRIIIRRRRRAAIAA"),
    (failed, "RRRRIIRRRRRRIIAAR"),
    (editing, "RRRRIIRRRRAAIIRIA"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(ScanPhase.allCases))
  for (state, expected) in rows {
    let frame = state.captureID ?? staleID()
    let save = state.pendingSave?.id ?? staleID()
    let events: [ScanEvent] = [
      .begin, .open, .resume(confirmedUnchanged: true), .capture,
      .captured(frame, try observation(.front)), .captureFailed(frame, .captureFailed),
      .accept, .retake, .editReview(.center(.orange)),
      .updateReviewObservation(try observation(.front)),
      .correct(.front, .rotate(.clockwise)),
      .recapture(.front), .saved(save), .saveFailed(save), .retrySave, .interrupt(.background),
      .cancel,
    ]
    #expect(expected.count == events.count)
    for (index, pair) in zip(events, expected).enumerated() {
      let result = step(state, pair.0)
      let code: Character
      switch result.disposition {
      case .accepted: code = "A"
      case .ignored: code = "I"
      case .rejected(.unavailableEvent): code = "R"
      default: code = "?"
      }
      #expect(code == pair.1, "phase=\(state.phase), event=\(index)")
      if code != "A" { #expect(result.workflow == state && result.commands.isEmpty) }
    }
  }
}
