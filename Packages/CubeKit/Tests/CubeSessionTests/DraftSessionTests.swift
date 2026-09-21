import CubeCore
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

func draftSavingSession() throws -> Session {
  let transition = apply(try editor(), .editDraft(.centers(try archivePalette())))
  try #require(transition.disposition == .accepted)
  try #require(transition.session.phase == .savingDraft)
  return transition.session
}

@Test(
  "V09/V11: edits emit concrete saves; only matching success enables further edits or validation")
func draftSaveBarrier() throws {
  let editing = try editor()
  let changed = apply(editing, .editDraft(.centers(try archivePalette())))
  #expect(changed.disposition == .accepted)
  #expect(changed.session.phase == .savingDraft)
  let save = try #require(changed.session.pendingDraftSave)
  #expect(save.draft.missingCount == 48)
  #expect(save.id.revision == editing.revision + 1)
  #expect(save.draft.revision == save.id.revision)
  #expect(changed.session.durableDraft == nil)
  if case .saveDraft(let command) = changed.commands.first {
    #expect(command == save)
  } else {
    Issue.record("Editing must emit the concrete snapshot to save")
  }
  #expect(apply(changed.session, .validateDraft).disposition == .rejected(.unavailableEvent))
  #expect(
    apply(changed.session, .editDraft(.rotate(.front, .clockwise))).disposition
      == .rejected(.unavailableEvent))
  let stale = SaveID(revision: save.id.revision, sequence: save.id.sequence + 1)
  #expect(apply(changed.session, .draftPersisted(stale)).disposition == .ignored)
  let saved = apply(changed.session, .draftPersisted(save.id)).session
  #expect(saved.phase == .editing)
  #expect(saved.durableDraft == save.draft)
  #expect(saved.pendingDraftSave == nil)
  #expect(apply(saved, .validateDraft).disposition == .rejected(.draft(.incomplete)))
  let next = apply(saved, .editDraft(.sticker(face: .front, row: 0, column: 0, color: .red)))
    .session
  #expect(next.draft?.cells[18] == .red)
  #expect(next.durableDraft == save.draft)
  #expect(next.revision == saved.revision + 1)
}

@Test(
  "V11: failed draft save retains edits, requires a successful retry, and ignores old callbacks")
func draftSaveFailure() throws {
  let saving = try draftSavingSession()
  let request = try #require(saving.pendingDraftSave)
  let failed = apply(saving, .draftPersistFailed(request.id)).session
  #expect(failed.phase == .draftStorageError)
  #expect(failed.draft == request.draft)
  #expect(failed.durableDraft == nil)
  #expect(apply(failed, .cancel).disposition == .rejected(.unavailableEvent))
  let retry = apply(failed, .retryDraftSave).session
  let retried = try #require(retry.pendingDraftSave)
  #expect(retried.id != request.id)
  #expect(retried.draft == request.draft)
  #expect(apply(retry, .draftPersisted(request.id)).disposition == .ignored)
  #expect(apply(retry, .draftPersisted(retried.id)).session.durableDraft == request.draft)

}

@Test("V11: closing during draft save waits for success; restored partial draft remains editable")
func draftExitAndRestore() throws {
  let saving = try draftSavingSession()
  let request = try #require(saving.pendingDraftSave)
  let exiting = apply(saving, .cancel).session
  #expect(exiting.phase == .savingDraft)
  let home = apply(exiting, .draftPersisted(request.id)).session
  #expect(home.phase == .home)
  #expect(home.draft == request.draft)
  #expect(apply(home, .resume).session.phase == .editing)
  let restored = Session(restoringDraft: request.draft)
  #expect(restored.phase == .editing)
  #expect(restored.draft == request.draft && restored.durableDraft == request.draft)
  #expect(restored.hasWork)
  #expect(restored.confirmedCube == nil)
}

@Test("V09: draft actions have explicit outcomes in every implemented phase")
func draftEventMatrix() throws {
  let palette = try archivePalette()
  let editing = try editor()
  let saving = try draftSavingSession()
  let saveID = try #require(saving.pendingDraftSave).id
  let failed = apply(saving, .draftPersistFailed(saveID)).session
  let ready = apply(saving, .draftPersisted(saveID)).session
  let complete = Session(restoringDraft: try filledDraft(.solved, palette: palette))
  let solving = try solvingSession()
  let preparing = try preparingSession()
  let guide = try durableGuide()
  let acknowledging = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let storageError = apply(
    acknowledging, .persistFailed(try #require(acknowledging.pendingSave).id)
  ).session
  var invalidFaces = Facelets.solved.faces
  invalidFaces[0] = .right
  // Columns: centers, sticker, rotation, validation, retry, save success, save failure.
  let deleting = try deletingSession()
  let deletionError = apply(deleting, .deletionFailed(try #require(deleting.pendingDeletion)))
    .session
  let rows: [(Session, String)] = [
    (Session(), "RRRRRII"), (editing, "ARRRRII"),
    (deleting, "RRRRRII"), (deletionError, "RRRRRII"),
    (saving, "RRRRRAA"), (failed, "RRRRAII"),
    (ready, "AAARRII"), (complete, "AAAARII"),
    (apply(editing, .validate(try Facelets(invalidFaces))).session, "RRRRRII"),
    (apply(editing, .validate(.solved)).session, "RRRRRII"),
    (try offeredSession(), "RRRRRII"), (solving, "RRRRRII"),
    (apply(solving, response(solving, outcome: .timedOut)).session, "RRRRRII"),
    (preparing, "RRRRRII"), (apply(preparing, .background).session, "RRRRRII"),
    (guide, "RRRRRII"), (acknowledging, "RRRRRII"), (storageError, "RRRRRII"),
    (apply(storageError, .compare(.uncertain)).session, "RRRRRII"),
    (try finishedGuide(), "RRRRRII"),
  ]
  #expect(Set(rows.map { $0.0.phase }) == Set(SessionPhase.allCases))
  for (state, codes) in rows {
    let id = state.pendingDraftSave?.id ?? SaveID(revision: state.revision, sequence: .max)
    let events: [SessionEvent] = [
      .editDraft(.centers(palette)),
      .editDraft(.sticker(face: .front, row: 0, column: 0, color: .red)),
      .editDraft(.rotate(.front, .clockwise)), .validateDraft, .retryDraftSave,
      .draftPersisted(id), .draftPersistFailed(id),
    ]
    try #require(events.count == codes.count)
    for (event, code) in zip(events, codes) {
      let result = apply(state, event)
      let actual: Character
      switch result.disposition {
      case .accepted: actual = "A"
      case .ignored: actual = "I"
      case .rejected: actual = "R"
      }
      #expect(actual == code, "\(state.phase) + \(event)")
      if code != "A" { #expect(result.session == state && result.commands.isEmpty) }
    }
  }
}

@Test("V09/V11: real reducer saves each draft revision before validating and solving")
func durableDraftToRealSolver() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let palette = try archivePalette()
  let literal = try Facelets(notation: literalRight)
  var session = try editor()
  var edits: [DraftEdit] = [.centers(palette)]
  for face in Face.allCases {
    for index in 0..<9 where index != 4 {
      let canonical = literal.faces[Int(face.rawValue) * 9 + index]
      edits.append(
        .sticker(
          face: face, row: index / 3, column: index % 3,
          color: palette.colors[Int(canonical.rawValue)]))
    }
  }
  for edit in edits {
    let transition = apply(session, .editDraft(edit))
    guard case .saveDraft(let request) = transition.commands.first else {
      Issue.record("Every edit must produce a real durable save command")
      return
    }
    try await store.saveDraft(request.draft, lease: store.currentLease())
    session = apply(transition.session, .draftPersisted(request.id)).session
  }
  #expect(try await store.loadDraft() == session.draft)
  let reviewed = apply(session, .validateDraft).session
  #expect(reviewed.phase == .offer)
  #expect(reviewed.confirmedCube?.facelets == literal)
  let solving = apply(reviewed, .consent(true)).session
  let cube = try #require(solving.confirmedCube)
  let response = await CubeSolver3.SolverService().solve(cube, revision: solving.revision)
  let preparing = apply(solving, .solveResult(response)).session
  let guide = try #require(preparing.pendingSave)
  try await store.save(guide, palette: palette, lease: store.currentLease())
  #expect(apply(preparing, .persisted(guide.id)).session.phase == .guide)
}

@Test("V09: draft validation cannot bypass saved colors and rejected edits preserve revision")
func draftValidationAndRevisionGuards() throws {
  let palette = try archivePalette()
  let partial = Session(restoringDraft: ManualDraft(palette: palette, revision: 10))
  let invalid = apply(partial, .editDraft(.sticker(face: .front, row: -1, column: 0, color: .red)))
  #expect(invalid.disposition == .rejected(.draft(.invalidCell)))
  #expect(invalid.session == partial && invalid.commands.isEmpty)
  let exhausted = Session(restoringDraft: ManualDraft(palette: palette, revision: .max))
  #expect(
    apply(exhausted, .editDraft(.centers(palette))).disposition == .rejected(.revisionExhausted))
  let literal = try Facelets(notation: literalRight)
  let complete = Session(restoringDraft: try filledDraft(literal, palette: palette))
  #expect(apply(complete, .validate(.solved)).disposition == .rejected(.unavailableEvent))
  let offered = apply(complete, .validateDraft).session
  #expect(offered.phase == .offer)
  let editing = apply(offered, .edit).session
  let changed = apply(editing, .editDraft(.rotate(.front, .clockwise))).session
  #expect(changed.revision == editing.revision + 1)
  #expect(changed.draft?.revision == changed.revision)
  #expect(changed.confirmedCube == nil)
  #expect(changed.durableDraft == complete.draft)
}
