import CubeCore
import CubeScan
import Foundation

public enum ScanPhase: String, CaseIterable, Sendable {
  case home, pausedCapture, scanning, freezing, faceReview, saving, storageError, editing
}
public enum ScanPauseReason: String, Sendable {
  case relaunch, background, permissionDenied, cameraUnavailable, thermal, orientationChanged
  case captureFailed, invalidObservation, auxiliaryNavigation
}
public enum ScanRejection: Equatable, Sendable {
  case unavailableEvent, confirmationRequired, revisionExhausted, invalidObservation
  case observation(ScanError)
}
public enum ScanDisposition: Equatable, Sendable {
  case accepted, ignored
  case rejected(ScanRejection)
}
public struct ScanOperationID: Equatable, Hashable, Sendable {
  public let workflow: UUID
  public let revision: UInt64
  public let sequence: UInt64
  public init(workflow: UUID, revision: UInt64, sequence: UInt64) {
    self.workflow = workflow
    self.revision = revision
    self.sequence = sequence
  }
}
public struct ScanSaveRequest: Equatable, Sendable {
  public let id: ScanOperationID
  public let scan: PendingScan
}
public enum ScanEdit: Equatable, Sendable {
  case sticker(row: Int, column: Int, color: CubeColor?)
  case center(CubeColor?)
  case rotate(QuarterTurns)
}
public enum ScanEvent: Sendable {
  case begin, open
  case resume(confirmedUnchanged: Bool)
  case capture
  case captured(ScanOperationID, ScanFace)
  case captureFailed(ScanOperationID, ScanPauseReason)
  case accept, retake
  case editReview(ScanEdit)
  case updateReviewObservation(ScanFace)
  case correct(Face, ScanEdit)
  case recapture(Face)
  case saved(ScanOperationID)
  case saveFailed(ScanOperationID)
  case retrySave
  case interrupt(ScanPauseReason)
  case cancel
}
public enum ScanCommand: Equatable, Sendable {
  case startCapture(Face)
  case stopCapture, discardFrame
  case freeze(ScanOperationID, Face)
  case save(ScanSaveRequest)
}
public struct ScanWorkflow: Equatable, Sendable {
  public fileprivate(set) var phase: ScanPhase
  public fileprivate(set) var durable: PendingScan?
  public fileprivate(set) var target: Face?
  public fileprivate(set) var review: ScanFace?
  public fileprivate(set) var captureID: ScanOperationID?
  public fileprivate(set) var pendingSave: ScanSaveRequest?
  public fileprivate(set) var pauseReason: ScanPauseReason?
  fileprivate var input: PendingScan
  fileprivate let identity = UUID()
  fileprivate var sequence: UInt64 = 0
  fileprivate var afterSave: ScanPhase = .scanning

  public init(starting scan: PendingScan) throws {
    guard scan.draft.acceptedCount == 0 else { throw ArchiveError.invalidProgress }
    input = scan
    target = scan.draft.nextSlot
    phase = .home
  }
  public init(restoring scan: PendingScan) {
    input = scan
    durable = scan
    target = scan.draft.nextSlot
    phase = target == nil ? .editing : .pausedCapture
    pauseReason = target == nil ? nil : .relaunch
  }
  init(restoring scan: PendingScan, sequence: UInt64) {
    self.init(restoring: scan)
    self.sequence = sequence
  }
}
public struct ScanTransition: Sendable {
  public let workflow: ScanWorkflow
  public let disposition: ScanDisposition
  public let commands: [ScanCommand]
}
public enum ScanReducer {
  public static func reduce(_ workflow: ScanWorkflow, event: ScanEvent) -> ScanTransition {
    func rejected(_ reason: ScanRejection = .unavailableEvent) -> ScanTransition {
      ScanTransition(workflow: workflow, disposition: .rejected(reason), commands: [])
    }
    func ignored() -> ScanTransition {
      ScanTransition(workflow: workflow, disposition: .ignored, commands: [])
    }
    var next = workflow
    var commands: [ScanCommand] = []
    func operationID(revision: UInt64) throws -> ScanOperationID {
      let (sequence, overflow) = next.sequence.addingReportingOverflow(1)
      guard !overflow else { throw ScanError.revisionExhausted }
      next.sequence = sequence
      return ScanOperationID(workflow: next.identity, revision: revision, sequence: sequence)
    }
    func save(_ scan: PendingScan, then phase: ScanPhase) throws {
      let request = try ScanSaveRequest(id: operationID(revision: scan.draft.revision), scan: scan)
      next.pendingSave = request
      next.afterSave = phase
      next.phase = .saving
      commands.append(.save(request))
    }
    func withDraft(_ draft: ScanDraft) throws -> PendingScan {
      try PendingScan(
        draft: draft, purpose: workflow.input.purpose,
        retainedGuide: workflow.input.retainedGuide)
    }
    func edit(_ value: ScanFace, _ edit: ScanEdit) throws -> ScanFace {
      switch edit {
      case .sticker(let row, let column, let color):
        try value.setting(row: row, column: column, color: color)
      case .center(let color): try value.assigningCenter(color)
      case .rotate(let turns): try value.rotating(by: turns)
      }
    }
    func pause(_ reason: ScanPauseReason) {
      next.phase = .pausedCapture
      next.pauseReason = reason
      next.review = nil
      next.captureID = nil
      commands = [.stopCapture, .discardFrame]
    }
    do {
      switch event {
      case .begin:
        guard workflow.phase == .home, workflow.durable == nil else { return rejected() }
        try save(workflow.input, then: .scanning)
      case .open:
        guard workflow.phase == .home, workflow.durable != nil else { return rejected() }
        next.phase = workflow.target == nil ? .editing : .pausedCapture
      case .resume(let confirmed):
        guard workflow.phase == .pausedCapture else { return rejected() }
        guard confirmed else { return rejected(.confirmationRequired) }
        next.pauseReason = nil
        if let target = workflow.target {
          next.phase = .scanning
          commands = [.startCapture(target)]
        } else {
          next.phase = .editing
        }
      case .capture:
        if workflow.phase == .freezing { return ignored() }
        guard workflow.phase == .scanning, let target = workflow.target else { return rejected() }
        let id = try operationID(revision: workflow.input.draft.revision)
        next.captureID = id
        next.phase = .freezing
        commands = [.freeze(id, target)]
      case .captured(let id, let face):
        guard workflow.phase == .freezing, workflow.captureID == id else { return ignored() }
        guard workflow.target == face.slot else {
          pause(.invalidObservation)
          break
        }
        next.captureID = nil
        next.review = face
        next.phase = .faceReview
        commands = [.stopCapture]
      case .captureFailed(let id, let reason):
        guard workflow.phase == .freezing, workflow.captureID == id else { return ignored() }
        pause(reason)
      case .accept:
        if workflow.phase == .saving { return ignored() }
        guard workflow.phase == .faceReview, let review = workflow.review else { return rejected() }
        let scan = try withDraft(workflow.input.draft.accepting(review, replacing: true))
        commands = [.discardFrame]
        try save(scan, then: scan.draft.nextSlot == nil ? .editing : .scanning)
        next.review = nil
      case .retake:
        guard workflow.phase == .faceReview, let target = workflow.target else { return rejected() }
        next.phase = .scanning
        next.review = nil
        commands = [.discardFrame, .startCapture(target)]
      case .editReview(let correction):
        guard workflow.phase == .faceReview, let review = workflow.review else { return rejected() }
        next.review = try edit(review, correction)
      case .updateReviewObservation(let observation):
        guard workflow.phase == .faceReview, let review = workflow.review else { return rejected() }
        guard observation.slot == review.slot else { return rejected(.invalidObservation) }
        let rotatedObservation: ScanFace
        switch review.correctionTurns {
        case 0: rotatedObservation = observation
        case 1: rotatedObservation = try observation.rotating(by: .clockwise)
        case 2: rotatedObservation = try observation.rotating(by: .half)
        case 3: rotatedObservation = try observation.rotating(by: .counterclockwise)
        default: return rejected(.invalidObservation)
        }
        next.review = try ScanFace(
          slot: review.slot, measurements: rotatedObservation.measurements,
          metadata: observation.metadata, centerName: review.centerName,
          manualOverrides: review.manualOverrides, correctionTurns: review.correctionTurns)
      case .correct(let slot, let correction):
        guard workflow.phase == .editing,
          let face = workflow.input.draft.faces[Int(slot.rawValue)]
        else { return rejected() }
        let updated = try edit(face, correction)
        let scan = try withDraft(workflow.input.draft.accepting(updated, replacing: true))
        try save(scan, then: .editing)
      case .recapture(let slot):
        guard workflow.phase == .editing,
          workflow.input.draft.faces[Int(slot.rawValue)] != nil
        else { return rejected() }
        next.target = slot
        next.phase = .pausedCapture
        next.pauseReason = nil
      case .saved(let id):
        guard workflow.phase == .saving, let request = workflow.pendingSave, request.id == id else {
          return ignored()
        }
        next.input = request.scan
        next.durable = request.scan
        next.pendingSave = nil
        next.target = request.scan.draft.nextSlot
        next.phase = workflow.afterSave
        if next.phase == .scanning {
          if let target = next.target {
            commands = [.startCapture(target)]
          } else {
            next.phase = .editing
          }
        }
      case .saveFailed(let id):
        guard workflow.phase == .saving, workflow.pendingSave?.id == id else { return ignored() }
        next.phase = .storageError
      case .retrySave:
        if workflow.phase == .saving { return ignored() }
        guard workflow.phase == .storageError, let request = workflow.pendingSave else {
          return rejected()
        }
        try save(request.scan, then: workflow.afterSave)
      case .interrupt(let reason):
        switch workflow.phase {
        case .scanning, .freezing, .faceReview: pause(reason)
        case .saving, .storageError:
          if workflow.afterSave != .home { next.afterSave = .pausedCapture }
          next.pauseReason = reason
          commands = [.stopCapture, .discardFrame]
        default: return ignored()
        }
      case .cancel:
        switch workflow.phase {
        case .home: return ignored()
        case .storageError: return rejected()
        case .saving: next.afterSave = .home
        default:
          next.phase = .home
          next.review = nil
          next.captureID = nil
        }
        commands = [.stopCapture, .discardFrame]
      }
    } catch ScanError.revisionExhausted {
      return rejected(.revisionExhausted)
    } catch let error as ScanError {
      return rejected(.observation(error))
    } catch {
      return rejected(.invalidObservation)
    }
    return ScanTransition(workflow: next, disposition: .accepted, commands: commands)
  }
}
