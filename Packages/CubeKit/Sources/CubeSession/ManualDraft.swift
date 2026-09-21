import CubeCore

public enum DraftError: Error, Equatable {
  case invalidCell, centerRequiresAssignment, incomplete, invalidShape, revisionExhausted
}

/// Semantic colors remain independent of the canonical solver labels.
public struct ManualDraft: Equatable, Sendable, Codable {
  public let palette: CenterPalette
  public let cells: [CubeColor?]
  public let revision: UInt64
  public var missingCount: Int { cells.filter { $0 == nil }.count }
  public init(palette: CenterPalette, revision: UInt64 = 0) {
    self.palette = palette
    self.revision = revision
    var cells: [CubeColor?] = Array(repeating: nil, count: 54)
    for face in Face.allCases {
      cells[Int(face.rawValue) * 9 + 4] = palette.colors[Int(face.rawValue)]
    }
    self.cells = cells
  }
  private init(palette: CenterPalette, cells: [CubeColor?], revision: UInt64) {
    self.palette = palette
    self.cells = cells
    self.revision = revision
  }
  private func nextRevision() throws -> UInt64 {
    let (next, overflow) = revision.addingReportingOverflow(1)
    guard !overflow else { throw DraftError.revisionExhausted }
    return next
  }
  public func setting(face: Face, row: Int, column: Int, color: CubeColor?) throws -> ManualDraft {
    guard (0..<3).contains(row), (0..<3).contains(column) else { throw DraftError.invalidCell }
    guard row != 1 || column != 1 else { throw DraftError.centerRequiresAssignment }
    var cells = cells
    cells[Int(face.rawValue) * 9 + row * 3 + column] = color
    return try ManualDraft(palette: palette, cells: cells, revision: nextRevision())
  }
  public func assigningCenters(_ palette: CenterPalette) throws -> ManualDraft {
    var cells = cells
    for face in Face.allCases {
      cells[Int(face.rawValue) * 9 + 4] = palette.colors[Int(face.rawValue)]
    }
    return try ManualDraft(palette: palette, cells: cells, revision: nextRevision())
  }
  public func rotating(_ face: Face, by turns: QuarterTurns) throws -> ManualDraft {
    var cells = cells
    let base = Int(face.rawValue) * 9
    for _ in 0..<Int(turns.rawValue) {
      let before = cells
      for row in 0..<3 {
        for column in 0..<3 {
          cells[base + column * 3 + 2 - row] = before[base + row * 3 + column]
        }
      }
    }
    return try ManualDraft(palette: palette, cells: cells, revision: nextRevision())
  }
  public func canonicalFacelets() throws -> Facelets {
    let labels = Dictionary(uniqueKeysWithValues: zip(palette.colors, Face.allCases))
    return try Facelets(
      cells.map { color in
        guard let color else { throw DraftError.incomplete }
        guard let face = labels[color] else { throw DraftError.invalidShape }
        return face
      })
  }
  private enum CodingKeys: String, CodingKey { case palette, cells, revision }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let palette = try container.decode(CenterPalette.self, forKey: .palette)
    let revision = try container.decode(UInt64.self, forKey: .revision)
    var values = try container.nestedUnkeyedContainer(forKey: .cells)
    var cells: [CubeColor?] = []
    while !values.isAtEnd {
      guard cells.count < 54 else { throw DraftError.invalidShape }
      cells.append(try values.decode(CubeColor?.self))
    }
    guard cells.count == 54 else { throw DraftError.invalidShape }
    for face in Face.allCases {
      guard cells[Int(face.rawValue) * 9 + 4] == palette.colors[Int(face.rawValue)] else {
        throw DraftError.invalidShape
      }
    }
    self.init(palette: palette, cells: cells, revision: revision)
  }
}
