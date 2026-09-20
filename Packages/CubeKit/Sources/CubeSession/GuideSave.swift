import CubeCore

public struct SaveID: Equatable, Hashable, Sendable, Codable {
  public let revision: UInt64
  public let sequence: UInt64
  public init(revision: UInt64, sequence: UInt64) {
    self.revision = revision
    self.sequence = sequence
  }
}
public enum GuideSaveKind: Sendable { case preparation, acknowledgement }
public struct GuideSaveRequest: Equatable, Sendable {
  public let id: SaveID
  public let kind: GuideSaveKind
  public let progress: GuideProgress
  public let pendingPrepared: Bool
}
public enum PreviewStatus: Sendable { case idle, playing, paused, finished }
public struct PlaybackID: Equatable, Sendable {
  public let action: ActionID
  public let sequence: UInt64
  public init(action: ActionID, sequence: UInt64) {
    self.action = action
    self.sequence = sequence
  }
}
public enum PhysicalComparison: Sendable { case before, after, uncertain }
