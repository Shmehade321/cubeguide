import CryptoKit
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
}
public enum GuideArchive {
  public static let maximumBytes = 256 * 1024
  private struct Envelope: Codable {
    let schema: Int
    let payload: Data
    let checksum: String
  }
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
  }
  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  public static func encode(_ request: GuideSaveRequest, palette: CenterPalette) throws -> Data {
    let progress = request.progress
    guard request.id.revision == progress.revision, request.id.sequence > 0,
      request.pendingPrepared == (request.kind == .preparation),
      !request.pendingPrepared || !progress.isComplete,
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
      pendingAction: progress.pending?.id, pendingPrepared: request.pendingPrepared)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(payload)
    let result = try encoder.encode(Envelope(schema: 1, payload: bytes, checksum: hash(bytes)))
    guard result.count <= maximumBytes else { throw ArchiveError.sizeLimit }
    return result
  }
  public static func decode(_ data: Data) throws -> RestoredGuide {
    guard data.count <= maximumBytes else { throw ArchiveError.sizeLimit }
    let decoder = JSONDecoder()
    // Inspect the version before interpreting any version-specific payload fields.
    struct Version: Decodable { let schema: Int }
    guard try decoder.decode(Version.self, from: data).schema == 1 else {
      throw ArchiveError.unsupportedVersion
    }
    let envelope = try decoder.decode(Envelope.self, from: data)
    guard envelope.checksum == hash(envelope.payload) else { throw ArchiveError.corrupt }
    let payload = try decoder.decode(Payload.self, from: envelope.payload)
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
      !payload.pendingPrepared || !progress.isComplete
    else { throw ArchiveError.invalidProgress }
    return RestoredGuide(
      progress: progress, palette: payload.palette,
      saveID: payload.saveID, pendingPrepared: payload.pendingPrepared)
  }
}
