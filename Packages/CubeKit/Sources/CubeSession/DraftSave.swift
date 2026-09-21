import CubeCore

public enum DraftEdit: Sendable {
  case centers(CenterPalette)
  case sticker(face: Face, row: Int, column: Int, color: CubeColor?)
  case rotate(Face, QuarterTurns)
}
public struct DraftSaveRequest: Equatable, Sendable {
  public let id: SaveID
  public let draft: ManualDraft
}
