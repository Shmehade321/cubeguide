import CubeCore
import CubeSolver3

public enum SessionPhase: String, CaseIterable, Sendable {
  case home, editing, invalid, alreadySolved, offer, solving, solveError, preparingAction,
    resumeCheck, guide, savingAcknowledgement, storageError, expectedSolved, recovery
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
  case persisted(SaveID)
  case persistFailed(SaveID)
  case confirmAlignment, play, pause, replay
  case previewFinished(PlaybackID)
  case acknowledge(ActionID)
  case compare(PhysicalComparison)
}
public enum SessionCommand: Sendable {
  case solve(LegalCube, revision: UInt64, budget: SolveBudget)
  case cancelSolve(revision: UInt64)
  case saveGuide(GuideSaveRequest)
  case playPreview(GuideAction, PlaybackID, restart: Bool)
  case stopPreview, pausePreview
}
public struct Session: Equatable, Sendable {
  public fileprivate(set) var phase: SessionPhase = .home
  public fileprivate(set) var revision: UInt64
  public fileprivate(set) var hasWork = false
  public fileprivate(set) var confirmedCube: LegalCube?
  public fileprivate(set) var validationIssues: ValidationIssues?
  public var plan: VerifiedPlan? { guideProgress?.plan }
  public var pendingAction: GuideAction? { guideProgress?.pending }
  public fileprivate(set) var solveFailure: SolveOutcome?
  public fileprivate(set) var usedExtendedAttempt = false
  public fileprivate(set) var guideProgress: GuideProgress?
  public fileprivate(set) var pendingSave: GuideSaveRequest?
  public fileprivate(set) var preparationDurable = false
  public fileprivate(set) var aligned = false
  public fileprivate(set) var preview: PreviewStatus = .idle
  public fileprivate(set) var playbackID: PlaybackID?
  fileprivate var saveSequence: UInt64 = 0
  fileprivate var playbackSequence: UInt64 = 0
  fileprivate var interruptedSave = false
  fileprivate var failedSaveKind: GuideSaveKind?
  public init(revision: UInt64 = 0) { self.revision = revision }
  public init(restoring archive: RestoredGuide) throws {
    self.init(revision: archive.progress.revision)
    guideProgress = archive.progress
    confirmedCube = try CubeValidation.validate(archive.progress.plan.original).get()
    hasWork = true
    preparationDurable = archive.pendingPrepared
    saveSequence = archive.saveID.sequence
    phase = archive.progress.isComplete ? .expectedSolved : .resumeCheck
  }
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
    func beginSave(_ kind: GuideSaveKind, progress: GuideProgress?) -> Bool {
      guard let progress else { return false }
      let (sequence, overflow) = next.saveSequence.addingReportingOverflow(1)
      guard !overflow else {
        next.phase = .storageError
        next.failedSaveKind = kind
        return false
      }
      next.saveSequence = sequence
      let request = GuideSaveRequest(
        id: SaveID(revision: session.revision, sequence: sequence),
        kind: kind, progress: progress, pendingPrepared: kind == .preparation)
      next.pendingSave = request
      next.phase = kind == .preparation ? .preparingAction : .savingAcknowledgement
      commands.append(.saveGuide(request))
      return true
    }
    switch event {
    case .persisted(let id):
      guard let save = session.pendingSave, save.id == id else { return ignored() }
      next.pendingSave = nil
      next.guideProgress = save.progress
      next.preparationDurable = save.pendingPrepared
      next.failedSaveKind = nil
      next.preview = .idle
      next.playbackID = nil
      if save.progress.isComplete {
        next.phase = .expectedSolved
      } else if session.interruptedSave || session.phase == .resumeCheck || session.phase == .home {
        next.phase = session.phase == .home ? .home : .resumeCheck
      } else if save.kind == .acknowledgement {
        _ = beginSave(.preparation, progress: save.progress)
      } else {
        next.phase = .guide
      }
      next.interruptedSave = false
    case .confirmAlignment:
      guard session.phase == .guide, session.preparationDurable, session.pendingSave == nil,
        session.preview == .idle
      else { return rejected() }
      if session.aligned { return ignored() }
      next.aligned = true
    case .play, .replay:
      guard session.phase == .guide, session.preparationDurable, session.aligned,
        session.pendingSave == nil, let action = session.pendingAction
      else { return rejected() }
      if case .play = event, session.preview == .playing { return ignored() }
      let (sequence, overflow) = session.playbackSequence.addingReportingOverflow(1)
      guard !overflow else { return rejected(.revisionExhausted) }
      next.playbackSequence = sequence
      let id = PlaybackID(action: action.id, sequence: sequence)
      let restart: Bool
      if case .replay = event { restart = true } else { restart = session.preview != .paused }
      next.playbackID = id
      next.preview = .playing
      commands = [.stopPreview, .playPreview(action, id, restart: restart)]
      if !restart { commands.removeFirst() }
    case .pause:
      guard session.phase == .guide, session.preview == .playing else { return rejected() }
      next.preview = .paused
      next.playbackID = nil
      commands = [.pausePreview]
    case .previewFinished(let id):
      guard session.phase == .guide, session.preview == .playing, session.playbackID == id else {
        return ignored()
      }
      next.preview = .finished
      next.playbackID = nil
    case .acknowledge(let id):
      guard session.pendingAction?.id == id else { return ignored() }
      guard session.pendingSave == nil else { return ignored() }
      guard session.phase == .guide, session.aligned, session.preparationDurable,
        session.preview != .playing, session.preview != .paused,
        let candidate = try? session.guideProgress?.acknowledging(id)
      else { return rejected() }
      next.preview = .idle
      next.playbackID = nil
      commands = [.stopPreview]
      _ = beginSave(.acknowledgement, progress: candidate)
    case .persistFailed(let id):
      guard let request = session.pendingSave, request.id == id else { return ignored() }
      next.pendingSave = nil
      next.failedSaveKind = request.kind
      next.interruptedSave = false
      next.phase = .storageError
      next.aligned = false
      next.preview = .idle
      next.playbackID = nil
      commands = [.stopPreview]
    case .compare(let choice):
      guard [.resumeCheck, .storageError].contains(session.phase), session.pendingSave == nil,
        let progress = session.guideProgress, let action = progress.pending
      else { return rejected() }
      next.preview = .idle
      next.playbackID = nil
      commands = [.stopPreview]
      switch choice {
      case .uncertain:
        next.phase = .recovery
        next.aligned = false
      case .before:
        next.aligned = true
        next.failedSaveKind = nil
        if session.preparationDurable {
          next.phase = .guide
        } else {
          _ = beginSave(.preparation, progress: progress)
        }
      case .after:
        guard session.preparationDurable || session.failedSaveKind == .acknowledgement,
          let candidate = try? progress.acknowledging(action.id)
        else { return rejected() }
        next.aligned = true
        next.failedSaveKind = nil
        _ = beginSave(.acknowledgement, progress: candidate)
      }
    case .startManual(let replacing):
      guard session.phase == .home else { return rejected() }
      guard !session.hasWork || replacing else { return rejected(.replacementRequired) }
      let (revision, overflow) = session.revision.addingReportingOverflow(1)
      guard !overflow else { return rejected(.revisionExhausted) }
      next = Session(revision: revision)
      next.phase = .editing
      next.hasWork = true
    case .cancel, .background:
      if [.preparingAction, .guide, .savingAcknowledgement].contains(session.phase) {
        next.aligned = false
        next.preview = .idle
        next.playbackID = nil
        next.interruptedSave = session.pendingSave != nil
        commands = [.stopPreview]
        if session.phase != .savingAcknowledgement { next.phase = .resumeCheck }
      } else if session.phase == .recovery {
        if case .background = event { return ignored() }
        next.phase = session.guideProgress?.isComplete == true ? .expectedSolved : .resumeCheck
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
          [.editing, .invalid, .alreadySolved, .offer, .solveError, .resumeCheck, .storageError]
            .contains(
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
      next.guideProgress = nil
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
        do {
          next.guideProgress = try GuideProgress(plan: plan, revision: session.revision)
          guard next.pendingAction != nil else { throw GuidePlanningError.invalidState }
        } catch {
          next.guideProgress = nil
          next.phase = .solveError
          next.solveFailure = .invariantFailure
          return SessionTransition(session: next, disposition: .accepted, commands: [])
        }
        _ = beginSave(.preparation, progress: next.guideProgress)
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
