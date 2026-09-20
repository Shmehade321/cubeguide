import CubeCore
import CubeSolver3

public enum SessionPhase: String, CaseIterable, Sendable {
  case home, editing, invalid, alreadySolved, offer, solving, solveError, preparingAction,
    resumeCheck
}
public enum SessionRejection: Equatable, Sendable {
  case unavailableEvent, replacementRequired, revisionExhausted
}
public enum EventDisposition: Equatable, Sendable {
  case accepted, ignored
  case rejected(SessionRejection)
}
public enum SessionEvent: Sendable {
  case startManual(replacing: Bool)
  case edit
  case validate(Facelets)
  case consent(Bool)
  case cancel, background, resume, retryLonger
  case solveResult(SolverResponse)
}
public enum SessionCommand: Sendable {
  case solve(LegalCube, revision: UInt64, budget: SolveBudget)
  case cancelSolve(revision: UInt64)
  case prepareGuide(VerifiedPlan, revision: UInt64)
}
public struct Session: Equatable, Sendable {
  public fileprivate(set) var phase: SessionPhase = .home
  public fileprivate(set) var revision: UInt64
  public fileprivate(set) var hasWork = false
  public fileprivate(set) var confirmedCube: LegalCube?
  public fileprivate(set) var validationIssues: ValidationIssues?
  public fileprivate(set) var plan: VerifiedPlan?
  public fileprivate(set) var pendingAction: GuideAction?
  public fileprivate(set) var solveFailure: SolveOutcome?
  public fileprivate(set) var usedExtendedAttempt = false
  public init(revision: UInt64 = 0) { self.revision = revision }
}
public struct SessionTransition: Sendable {
  public let session: Session
  public let disposition: EventDisposition
  public let commands: [SessionCommand]
}
public enum SessionReducer {
  public static func reduce(_ session: Session, event: SessionEvent) -> SessionTransition {
    func rejected(_ reason: SessionRejection = .unavailableEvent) -> SessionTransition {
      SessionTransition(session: session, disposition: .rejected(reason), commands: [])
    }
    var next = session
    var commands: [SessionCommand] = []
    func ignored() -> SessionTransition {
      SessionTransition(session: session, disposition: .ignored, commands: [])
    }
    func advanceRevision() -> Bool {
      let (revision, overflow) = session.revision.addingReportingOverflow(1)
      guard !overflow else { return false }
      next.revision = revision
      return true
    }
    switch event {
    case .startManual(let replacing):
      guard session.phase == .home else { return rejected() }
      guard !session.hasWork || replacing else { return rejected(.replacementRequired) }
      let (revision, overflow) = session.revision.addingReportingOverflow(1)
      guard !overflow else { return rejected(.revisionExhausted) }
      next = Session(revision: revision)
      next.phase = .editing
      next.hasWork = true
    case .cancel, .background:
      if session.phase == .preparingAction {
        next.phase = .resumeCheck
      } else if session.phase == .solving {
        // At the final revision, leaving .solving still invalidates its callback;
        // further requests are rejected rather than wrapping the generation.
        _ = advanceRevision()
        next.phase = .offer
        commands = [.cancelSolve(revision: session.revision)]
      } else if case .background = event {
        return ignored()
      } else {
        guard
          [.editing, .invalid, .alreadySolved, .offer, .solveError, .resumeCheck].contains(
            session.phase)
        else {
          return rejected()
        }
        next.phase = .home
      }
    case .validate(let faces):
      guard session.phase == .editing else { return rejected() }
      let (revision, overflow) = session.revision.addingReportingOverflow(1)
      guard !overflow else { return rejected(.revisionExhausted) }
      next.revision = revision
      switch CubeValidation.validate(faces) {
      case .failure(let issues):
        next.phase = .invalid
        next.validationIssues = issues
        next.confirmedCube = nil
      case .success(let cube):
        next.confirmedCube = cube
        next.validationIssues = nil
        next.phase = faces == .solved ? .alreadySolved : .offer
      }
    case .consent(let accepted):
      guard session.phase == .offer, let cube = session.confirmedCube else { return rejected() }
      if accepted {
        let (revision, overflow) = session.revision.addingReportingOverflow(1)
        guard !overflow else { return rejected(.revisionExhausted) }
        next.revision = revision
        next.phase = .solving
        next.usedExtendedAttempt = false
        next.solveFailure = nil
        commands = [.solve(cube, revision: revision, budget: .standard)]
      } else {
        next.phase = .home
      }
    case .edit:
      guard
        [.editing, .invalid, .alreadySolved, .offer, .solveError].contains(
          session.phase)
      else {
        return rejected()
      }
      guard advanceRevision() else { return rejected(.revisionExhausted) }
      next.phase = .editing
      next.confirmedCube = nil
      next.validationIssues = nil
      next.plan = nil
      next.pendingAction = nil
      next.solveFailure = nil
      next.usedExtendedAttempt = false
    case .resume:
      guard session.phase == .home, session.hasWork else { return rejected() }
      if session.plan != nil, session.pendingAction != nil {
        next.phase = .resumeCheck
      } else if let cube = session.confirmedCube {
        next.phase = cube.facelets == .solved ? .alreadySolved : .offer
      } else {
        next.phase = .editing
      }
    case .retryLonger:
      guard session.phase == .solveError, session.solveFailure == .timedOut,
        !session.usedExtendedAttempt, let cube = session.confirmedCube
      else { return rejected() }
      guard advanceRevision() else { return rejected(.revisionExhausted) }
      next.phase = .solving
      next.usedExtendedAttempt = true
      next.solveFailure = nil
      commands = [.solve(cube, revision: next.revision, budget: .extended)]
    case .solveResult(let response):
      guard session.phase == .solving, response.revision == session.revision,
        let cube = session.confirmedCube
      else { return ignored() }
      switch response.outcome {
      case .verified(let plan):
        guard plan.original == cube.facelets else {
          next.phase = .solveError
          next.solveFailure = .verificationFailure
          return SessionTransition(session: next, disposition: .accepted, commands: [])
        }
        next.plan = plan
        do {
          guard let move = plan.moves.first else { throw GuidePlanningError.invalidState }
          next.pendingAction = try GuidePlanner.actions(
            for: move, at: .identity, state: plan.original,
            sessionRevision: session.revision, moveIndex: 0
          ).first
          guard next.pendingAction != nil else { throw GuidePlanningError.invalidState }
        } catch {
          next.plan = nil
          next.phase = .solveError
          next.solveFailure = .invariantFailure
          return SessionTransition(session: next, disposition: .accepted, commands: [])
        }
        next.phase = .preparingAction
        commands = [.prepareGuide(plan, revision: session.revision)]
      case .cancelled:
        next.phase = .offer
      case .invalidInput:
        // A job accepted a LegalCube, so contrary validation is an internal failure.
        next.phase = .solveError
        next.solveFailure = .invariantFailure
      default:
        next.phase = .solveError
        next.solveFailure = response.outcome
      }
    }
    return SessionTransition(session: next, disposition: .accepted, commands: commands)
  }
}
