import CubeCore
import Foundation

public enum ArchiveError: Error, Equatable {
  case sizeLimit, unsupportedVersion, corrupt, invalidProgress
}
public struct RestoredGuide: Equatable, Sendable {
  public let progress: GuideProgress
  public let palette: CenterPalette
  public let saveID: SaveID
  public let pendingPrepared: Bool
  public let completion: CompletionKind?
}
public enum GuideArchive {
  public static let maximumBytes = CheckedArchive.maximumBytes
  private struct Payload: Codable {
    let original: Facelets
    let moves: String
    let originalHash: String
    let resourceVersion: String
    let palette: CenterPalette
    let saveID: SaveID
    let acknowledgedActions: Int
    let moveIndex: Int
    let pose: CubeOrientation
    let state: Facelets
    let pendingAction: ActionID?
    let pendingPrepared: Bool
    let completion: CompletionKind?
  }
  private static func validCompletion(_ completion: CompletionKind?, progress: GuideProgress)
    -> Bool
  {
    guard let completion else { return true }
    guard progress.isComplete else { return false }
    switch completion {
    case .enteredColorsSolved:
      return progress.plan.original == .solved && progress.plan.moves.isEmpty
    case .userConfirmed: return !progress.plan.moves.isEmpty
    }
  }
  public static func encode(_ request: GuideSaveRequest, palette: CenterPalette) throws -> Data {
    let progress = request.progress
    guard request.id.revision == progress.revision, request.id.sequence > 0,
      request.pendingPrepared == (request.kind == .preparation),
      !request.pendingPrepared || !progress.isComplete,
      validCompletion(request.kind.completion, progress: progress),
      !progress.plan.resourceVersion.isEmpty,
      progress.plan.resourceVersion.utf8.count <= 256
    else { throw ArchiveError.invalidProgress }
    let payload = Payload(
      original: progress.plan.original,
      moves: progress.plan.moves.map(\.notation).joined(separator: " "),
      originalHash: progress.plan.originalStateHash,
      resourceVersion: progress.plan.resourceVersion, palette: palette,
      saveID: request.id, acknowledgedActions: progress.acknowledgedActions,
      moveIndex: progress.moveIndex, pose: progress.pose, state: progress.state,
      pendingAction: progress.pending?.id, pendingPrepared: request.pendingPrepared,
      completion: request.kind.completion)
    return try CheckedArchive.encode(payload)
  }
  public static func decode(_ data: Data) throws -> RestoredGuide {
    let payload = try CheckedArchive.decode(Payload.self, from: data)
    guard !payload.resourceVersion.isEmpty, payload.resourceVersion.utf8.count <= 256,
      payload.saveID.sequence > 0
    else { throw ArchiveError.invalidProgress }
    let cube = try CubeValidation.validate(payload.original).get()
    let plan = try Replay.verify(
      Move.parse(payload.moves), for: cube,
      resourceVersion: payload.resourceVersion
    ).get()
    let progress = try GuideProgress(
      plan: plan, revision: payload.saveID.revision,
      acknowledgedActions: payload.acknowledgedActions)
    guard payload.originalHash == plan.originalStateHash,
      payload.moveIndex == progress.moveIndex, payload.pose == progress.pose,
      payload.state == progress.state, payload.pendingAction == progress.pending?.id,
      !payload.pendingPrepared || !progress.isComplete,
      validCompletion(payload.completion, progress: progress)
    else { throw ArchiveError.invalidProgress }
    return RestoredGuide(
      progress: progress, palette: payload.palette,
      saveID: payload.saveID, pendingPrepared: payload.pendingPrepared,
      completion: payload.completion)
  }
}
