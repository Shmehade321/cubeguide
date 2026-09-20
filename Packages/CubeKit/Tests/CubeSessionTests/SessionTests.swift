import CubeCore
import CubeSolver3
import Testing

@testable import CubeSession

let literalRight = "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB"
func apply(_ session: Session, _ event: SessionEvent) -> SessionTransition {
  SessionReducer.reduce(session, event: event)
}
func editor() throws -> Session {
  let transition = apply(Session(), .startManual(replacing: false))
  try #require(transition.session.phase == .editing)
  return transition.session
}

@Test("V09: a new manual session is empty and existing work cannot be silently replaced")
func manualStartAndReplacement() throws {
  let initial = Session()
  let started = apply(initial, .startManual(replacing: false))
  #expect(started.disposition == .accepted)
  #expect(started.session.phase == .editing)
  #expect(started.session.revision == 1)
  #expect(started.session.hasWork)
  #expect(started.session.confirmedCube == nil)
  #expect(started.commands.isEmpty)
  let home = apply(started.session, .cancel)
  #expect(home.session.phase == .home)
  let refused = apply(home.session, .startManual(replacing: false))
  #expect(refused.disposition == .rejected(.replacementRequired))
  #expect(refused.session == home.session)
  let replaced = apply(home.session, .startManual(replacing: true))
  #expect(replaced.disposition == .accepted)
  #expect(replaced.session.phase == .editing)
  #expect(replaced.session.revision > home.session.revision)
}

@Test("V09: real validation separates solved, invalid and scrambled states without solving")
func classifyReviewedInput() throws {
  let editing = try editor()
  var invalid = Facelets.solved.faces
  invalid[0] = .right
  for (input, expected) in [
    (Facelets.solved, SessionPhase.alreadySolved),
    (try Facelets(invalid), .invalid),
    (try Facelets(notation: literalRight), .offer),
  ] {
    let transition = apply(editing, .validate(input))
    #expect(transition.disposition == .accepted)
    #expect(transition.session.phase == expected)
    #expect(transition.commands.isEmpty)
    #expect(transition.session.plan == nil)
    #expect(transition.session.revision > editing.revision)
    if expected == .invalid {
      #expect(transition.session.validationIssues != nil)
      #expect(transition.session.confirmedCube == nil)
    } else {
      #expect(transition.session.confirmedCube?.facelets == input)
    }
  }
}

@Test("V09: only consent to a confirmed legal scramble emits a solve request")
func consentBeforeSearch() throws {
  let editing = try editor()
  let offered = apply(editing, .validate(try Facelets(notation: literalRight))).session
  let declined = apply(offered, .consent(false))
  #expect(declined.session.phase == .home)
  #expect(declined.session.confirmedCube == offered.confirmedCube)
  #expect(declined.commands.isEmpty)
  let accepted = apply(offered, .consent(true))
  #expect(accepted.session.phase == .solving)
  #expect(accepted.commands.count == 1)
  if case .solve(let cube, let revision, let budget) = accepted.commands.first {
    #expect(cube.facelets.notation == literalRight)
    #expect(revision == accepted.session.revision)
    #expect(budget == .standard)
  } else {
    Issue.record("Consent must issue a real solve request")
  }
  for state in [Session(), editing, apply(editing, .validate(.solved)).session] {
    let transition = apply(state, .consent(true))
    #expect(transition.disposition == .rejected(.unavailableEvent))
    #expect(transition.session == state)
    #expect(transition.commands.isEmpty)
  }
}

@Test("V09: revision exhaustion rejects a new session without wrapping or changing work")
func revisionExhaustion() {
  let session = Session(revision: .max)
  let transition = apply(session, .startManual(replacing: true))
  #expect(transition.disposition == .rejected(.revisionExhausted))
  #expect(transition.session == session)
  #expect(transition.commands.isEmpty)
}

func offeredSession() throws -> Session {
  let result = apply(try editor(), .validate(try Facelets(notation: literalRight)))
  try #require(result.session.phase == .offer)
  return result.session
}
func solvingSession() throws -> Session {
  let result = apply(try offeredSession(), .consent(true))
  try #require(result.session.phase == .solving)
  return result.session
}
func response(_ state: Session, outcome: SolveOutcome, revision: UInt64? = nil) -> SessionEvent {
  .solveResult(
    SolverResponse(
      revision: revision ?? state.revision, outcome: outcome, elapsed: .zero, visitedNodes: 0))
}

@Test("V09: cancelling or backgrounding solve preserves input and invalidates delayed results")
func cancelAndStaleResults() throws {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  for event in [SessionEvent.cancel, .background] {
    let cancelled = apply(solving, event)
    #expect(cancelled.disposition == .accepted)
    #expect(cancelled.session.phase == .offer)
    #expect(cancelled.session.confirmedCube == solving.confirmedCube)
    #expect(cancelled.session.revision > solving.revision)
    #expect(cancelled.commands.count == 1)
    if case .cancelSolve(let revision) = cancelled.commands.first {
      #expect(revision == solving.revision)
    } else {
      Issue.record("Leaving search must cancel its worker")
    }
    let late = apply(cancelled.session, response(solving, outcome: .verified(plan)))
    #expect(late.disposition == .ignored)
    #expect(late.session == cancelled.session)
    #expect(late.commands.isEmpty)
  }
}

@Test("V09: accept only a matching verified plan and distinguish solve errors from invalid input")
func checkedSolveResults() throws {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  let accepted = apply(solving, response(solving, outcome: .verified(plan)))
  #expect(accepted.session.phase == .preparingAction)
  #expect(accepted.session.plan == plan)
  #expect(accepted.commands.count == 1)
  if case .saveGuide(let request) = accepted.commands.first {
    #expect(request.progress.plan == plan)
    #expect(request.id.revision == solving.revision)
  } else {
    Issue.record("Only the verified plan may enter action preparation")
  }
  let wrongCube = try CubeValidation.validate(.solved).get()
  let wrongPlan = try Replay.verify([], for: wrongCube, resourceVersion: "fixture").get()
  let wrong = apply(solving, response(solving, outcome: .verified(wrongPlan)))
  #expect(wrong.session.phase == .solveError)
  #expect(wrong.session.solveFailure == .verificationFailure)
  #expect(wrong.session.plan == nil)
  #expect(wrong.commands.isEmpty)
  for outcome in [
    SolveOutcome.timedOut, .resourceFailure("missing"), .verificationFailure, .invariantFailure,
  ] {
    let failed = apply(solving, response(solving, outcome: outcome))
    #expect(failed.session.phase == .solveError)
    #expect(failed.session.solveFailure == outcome)
    #expect(failed.session.confirmedCube == solving.confirmedCube)
    #expect(failed.session.validationIssues == nil)
    #expect(failed.commands.isEmpty)
  }
  let stale = apply(
    solving, response(solving, outcome: .verified(plan), revision: solving.revision - 1))
  #expect(stale.disposition == .ignored)
  #expect(stale.session == solving)
  let duplicate = apply(accepted.session, response(solving, outcome: .verified(plan)))
  #expect(duplicate.disposition == .ignored)
  #expect(duplicate.commands.isEmpty)
  let stopped = apply(solving, response(solving, outcome: .cancelled))
  #expect(stopped.session.phase == .offer)
}

@Test("V09: editing clears prior confirmation and resume retains the reviewed scan")
func editAndResume() throws {
  let offered = try offeredSession()
  let home = apply(offered, .consent(false)).session
  let resumed = apply(home, .resume)
  #expect(resumed.session.phase == .offer)
  #expect(resumed.session.confirmedCube == offered.confirmedCube)
  let editing = apply(offered, .edit)
  #expect(editing.session.phase == .editing)
  #expect(editing.session.confirmedCube == nil)
  #expect(editing.session.revision > offered.revision)
  let stopped = apply(editing.session, .cancel).session
  let resumedDraft = apply(stopped, .resume)
  #expect(resumedDraft.session.phase == .editing)
  #expect(resumedDraft.session.confirmedCube == nil)
  #expect(apply(Session(), .resume).disposition == .rejected(.unavailableEvent))
}

@Test("V09: extended retry requires a timeout and is offered only once for that request")
func extendedRetry() throws {
  let solving = try solvingSession()
  let timed = apply(solving, response(solving, outcome: .timedOut)).session
  let retry = apply(timed, .retryLonger)
  #expect(retry.session.phase == .solving)
  #expect(retry.session.usedExtendedAttempt)
  #expect(retry.session.revision > solving.revision)
  if case .solve(let cube, let revision, let budget) = retry.commands.first {
    #expect(cube == solving.confirmedCube)
    #expect(revision == retry.session.revision)
    #expect(budget == .extended)
  } else {
    Issue.record("Explicit longer retry must use extended budget")
  }
  let timedAgain = apply(retry.session, response(retry.session, outcome: .timedOut)).session
  #expect(apply(timedAgain, .retryLonger).disposition == .rejected(.unavailableEvent))
  let broken = apply(solving, response(solving, outcome: .resourceFailure("missing"))).session
  #expect(apply(broken, .retryLonger).disposition == .rejected(.unavailableEvent))
}

@Test(
  "V09: every implemented workflow phase/event pair has an explicit accepted, ignored or rejected outcome"
)
func preGuideTransitionMatrix() throws {
  let editing = try editor()
  var bad = Facelets.solved.faces
  bad[0] = .right
  let invalid = apply(editing, .validate(try Facelets(bad))).session
  let solved = apply(editing, .validate(.solved)).session
  let offered = try offeredSession()
  let solving = try solvingSession()
  let error = apply(solving, response(solving, outcome: .timedOut)).session
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  let prepared = apply(solving, response(solving, outcome: .verified(plan))).session
  let resumeCheck = apply(prepared, .background).session
  let guide = try durableGuide()
  let saving = apply(guide, .acknowledge(try #require(guide.pendingAction).id)).session
  let storageError = apply(saving, .persistFailed(try #require(saving.pendingSave).id)).session
  let recovery = apply(storageError, .compare(.uncertain)).session
  let expectedSolved = try finishedGuide()
  // Columns: start, edit, validate, yes, no, cancel, background, resume, longer, result.
  // A = accepted; R = rejected; I = ignored. Extend with each new workflow phase.
  let rows: [(Session, SessionPhase, String)] = [
    (Session(), .home, "ARRRRRIRRI"),
    (editing, .editing, "RAARRAIRRI"),
    (invalid, .invalid, "RARRRAIRRI"),
    (solved, .alreadySolved, "RARRRAIRRI"),
    (offered, .offer, "RARAAAIRRI"),
    (solving, .solving, "RRRRRAARRA"),
    (error, .solveError, "RARRRAIRAI"),
    (prepared, .preparingAction, "RRRRRAARRI"),
    (resumeCheck, .resumeCheck, "RRRRRAIRRI"),
    (guide, .guide, "RRRRRAARRI"),
    (saving, .savingAcknowledgement, "RRRRRAARRI"),
    (storageError, .storageError, "RRRRRAIRRI"),
    (recovery, .recovery, "RRRRRAIRRI"),
    (expectedSolved, .expectedSolved, "RRRRRRIRRI"),
  ]
  #expect(Set(rows.map { $0.1 }) == Set(SessionPhase.allCases))
  for (state, phase, expected) in rows {
    try #require(state.phase == phase)
    let events: [SessionEvent] = [
      .startManual(replacing: false), .edit,
      .validate(try Facelets(notation: literalRight)), .consent(true), .consent(false),
      .cancel, .background, .resume, .retryLonger, response(state, outcome: .timedOut),
    ]
    try #require(events.count == expected.count)
    for (event, code) in zip(events, expected) {
      let transition = apply(state, event)
      switch code {
      case "A": #expect(transition.disposition == .accepted)
      case "I":
        #expect(transition.disposition == .ignored)
        #expect(transition.session == state)
        #expect(transition.commands.isEmpty)
      default:
        #expect(transition.disposition == .rejected(.unavailableEvent))
        #expect(transition.session == state)
        #expect(transition.commands.isEmpty)
      }
    }
  }
}

@Test("V09: the session's solve command executes the real solver and returns only a verified plan")
func sessionSolverIntegration() async throws {
  let accepted = apply(try offeredSession(), .consent(true))
  guard case .solve(let cube, let revision, let budget) = accepted.commands.first else {
    Issue.record("Expected real solve command")
    return
  }
  let answer = await SolverService().solve(cube, revision: revision, budget: budget)
  let ready = apply(accepted.session, .solveResult(answer))
  #expect(ready.session.phase == .preparingAction)
  let plan = try #require(ready.session.plan)
  #expect(plan.original == cube.facelets)
  #expect(cube.facelets.applying(plan.moves) == .solved)
}

@Test("V09: cancelling at the maximum revision remains possible and cannot accept its late result")
func cancelAtFinalRevision() throws {
  let editing = apply(Session(revision: .max - 3), .startManual(replacing: false)).session
  let offered = apply(editing, .validate(try Facelets(notation: literalRight))).session
  let solving = apply(offered, .consent(true)).session
  try #require(solving.phase == .solving && solving.revision == .max)
  let cancelled = apply(solving, .cancel)
  #expect(cancelled.disposition == .accepted)
  #expect(cancelled.session.phase == .offer)
  #expect(cancelled.session.revision == .max)
  #expect(cancelled.commands.count == 1)
  #expect(apply(cancelled.session, response(solving, outcome: .timedOut)).disposition == .ignored)
  #expect(apply(cancelled.session, .consent(true)).disposition == .rejected(.revisionExhausted))
}

@Test("V09: contradictory worker invalidity cannot relabel already validated input")
func workerInvalidityIsInvariantFailure() throws {
  var bad = Facelets.solved.faces
  bad[0] = .right
  guard case .failure(let issues) = CubeValidation.validate(try Facelets(bad)) else {
    Issue.record("Wrong count fixture must be invalid")
    return
  }
  let solving = try solvingSession()
  let result = apply(solving, response(solving, outcome: .invalidInput(issues)))
  #expect(result.session.phase == .solveError)
  #expect(result.session.solveFailure == .invariantFailure)
  #expect(result.session.confirmedCube == solving.confirmedCube)
  #expect(result.session.validationIssues == nil)
}

@Test("V09: action preparation owns a deterministic pending action before any preview can start")
func preparedActionIdentity() throws {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  let ready = apply(solving, response(solving, outcome: .verified(plan))).session
  let pending = try #require(ready.pendingAction)
  #expect(pending.id.sessionRevision == solving.revision)
  #expect(pending.id.moveIndex == 0)
  #expect(pending.id.actionIndex == 0)
  #expect(pending.operation == .regrip(.yawLeft))
  #expect(pending.before == cube.facelets)
  #expect(pending.after == cube.facelets)
  #expect(ready.phase == .preparingAction)
}

@Test(
  "V09: interruption during preparation enters comparison, retains the action and resumes safely from Home"
)
func preparationInterruption() throws {
  let solving = try solvingSession()
  let cube = try #require(solving.confirmedCube)
  let plan = try Replay.verify(
    [Move(face: .right, turns: .counterclockwise)], for: cube, resourceVersion: "fixture"
  ).get()
  let ready = apply(solving, response(solving, outcome: .verified(plan))).session
  for event in [SessionEvent.cancel, .background] {
    let paused = apply(ready, event)
    #expect(paused.disposition == .accepted)
    #expect(paused.session.phase == .resumeCheck)
    #expect(paused.session.pendingAction == ready.pendingAction)
    #expect(paused.session.plan == plan)
    let home = apply(paused.session, .cancel)
    #expect(home.session.phase == .home)
    let resumed = apply(home.session, .resume)
    #expect(resumed.session.phase == .resumeCheck)
    #expect(resumed.session.pendingAction == ready.pendingAction)
  }
}
