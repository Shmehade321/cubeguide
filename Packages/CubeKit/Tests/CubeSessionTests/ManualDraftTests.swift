import CubeCore
import Foundation
import Testing

@testable import CubeSession

@Test("R03/R18: manual draft contains explicit centers and 48 empty stickers")
func draftStartsEmpty() throws {
  let palette = try archivePalette()
  let draft = ManualDraft(palette: palette, revision: 7)
  #expect(draft.revision == 7)
  #expect(draft.cells.count == 54)
  #expect(draft.missingCount == 48)
  for face in Face.allCases {
    for offset in 0..<9 {
      #expect(
        draft.cells[Int(face.rawValue) * 9 + offset]
          == (offset == 4 ? palette.colors[Int(face.rawValue)] : nil))
    }
  }
  #expect(throws: DraftError.incomplete) { try draft.canonicalFacelets() }
}

@Test("R03/R18: draft edits address exactly one cell, permit clearing and invalidate old revisions")
func draftEdits() throws {
  let draft = ManualDraft(palette: try archivePalette(), revision: 10)
  let edited = try draft.setting(face: .back, row: 2, column: 1, color: .red)
  #expect(edited.cells[52] == .red)
  #expect(edited.missingCount == 47)
  #expect(edited.revision == 11)
  #expect(draft.cells[52] == nil)
  let cleared = try edited.setting(face: .back, row: 2, column: 1, color: nil)
  #expect(cleared.cells == draft.cells)
  #expect(cleared.revision == 12)
  for (row, column) in [(-1, 0), (3, 0), (0, -1), (0, 3), (Int.max, 0)] {
    #expect(throws: DraftError.invalidCell) {
      try draft.setting(face: .front, row: row, column: column, color: .white)
    }
  }
  #expect(throws: DraftError.centerRequiresAssignment) {
    try draft.setting(face: .front, row: 1, column: 1, color: .white)
  }
  let final = ManualDraft(palette: draft.palette, revision: .max)
  #expect(throws: DraftError.revisionExhausted) {
    try final.setting(face: .up, row: 0, column: 0, color: .white)
  }
}

@Test("R03: changing center assignments preserves entered sticker colors and increments revision")
func draftCenterReassignment() throws {
  let draft = try ManualDraft(palette: archivePalette()).setting(
    face: .front, row: 0, column: 0, color: .orange)
  let newPalette = try CenterPalette([.red, .blue, .yellow, .green, .white, .orange])
  let changed = try draft.assigningCenters(newPalette)
  #expect(changed.palette == newPalette)
  #expect(changed.revision == draft.revision + 1)
  #expect(changed.cells[18] == .orange)
  for face in Face.allCases {
    #expect(changed.cells[Int(face.rawValue) * 9 + 4] == newPalette.colors[Int(face.rawValue)])
  }
}

@Test("R03: face correction rotates entered and empty cells clockwise without changing other faces")
func draftFaceRotation() throws {
  let palette = try archivePalette()
  for face in Face.allCases {
    var draft = ManualDraft(palette: palette)
    let pattern: [CubeColor?] = [
      .white, .yellow, .red, .blue, palette.colors[Int(face.rawValue)], .green, nil, .white,
      .yellow,
    ]
    for index in 0..<9 where index != 4 {
      draft = try draft.setting(
        face: face, row: index / 3, column: index % 3, color: pattern[index])
    }
    let rotated = try draft.rotating(face, by: .clockwise)
    let base = Int(face.rawValue) * 9
    let expected: [CubeColor?] = [
      nil, .blue, .white, .white, pattern[4], .yellow, .yellow, .green, .red,
    ]
    #expect(Array(rotated.cells[base..<base + 9]) == expected)
    #expect(rotated.revision == draft.revision + 1)
    for index in 0..<54 where !(base..<base + 9).contains(index) {
      #expect(rotated.cells[index] == draft.cells[index])
    }
    #expect(try rotated.rotating(face, by: .counterclockwise).cells == draft.cells)
    let half = try draft.rotating(face, by: .half)
    #expect(try half.cells == rotated.rotating(face, by: .clockwise).cells)
  }
}

func filledDraft(_ facelets: Facelets, palette: CenterPalette) throws -> ManualDraft {
  var draft = ManualDraft(palette: palette)
  for face in Face.allCases {
    for index in 0..<9 where index != 4 {
      let canonical = facelets.faces[Int(face.rawValue) * 9 + index]
      draft = try draft.setting(
        face: face, row: index / 3, column: index % 3,
        color: palette.colors[Int(canonical.rawValue)])
    }
  }
  return draft
}

@Test(
  "R03/R04: all 54 reviewed colors normalize using explicit centers, without guessed corrections")
func draftCanonicalConversion() throws {
  let literal = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
  let palette = try archivePalette()
  let draft = try filledDraft(literal, palette: palette)
  #expect(draft.missingCount == 0)
  #expect(try draft.canonicalFacelets() == literal)
  #expect(try CubeValidation.validate(draft.canonicalFacelets()).get().facelets == literal)
  let solved = try filledDraft(.solved, palette: palette)
  #expect(try solved.canonicalFacelets() == .solved)
  let invalid = try solved.setting(face: .front, row: 0, column: 0, color: palette.colors[0])
  let raw = try invalid.canonicalFacelets()
  #expect(raw.faces[18] == .up)
  if case .success = CubeValidation.validate(raw) {
    Issue.record("Wrong color count must remain invalid")
  }
  #expect(try invalid.setting(face: .back, row: 2, column: 2, color: nil).missingCount == 1)
  #expect(throws: DraftError.incomplete) {
    try invalid.setting(face: .back, row: 2, column: 2, color: nil).canonicalFacelets()
  }
}

@Test("R18: decoded drafts preserve partial colors and reject invalid shape or centers")
func draftDecodeBounds() throws {
  let partial = try ManualDraft(palette: archivePalette(), revision: 42)
    .setting(face: .right, row: 2, column: 0, color: .blue)
  let bytes = try JSONEncoder().encode(partial)
  #expect(try JSONDecoder().decode(ManualDraft.self, from: bytes) == partial)
  let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  let originalCells = try #require(original["cells"] as? [Any])
  for count in [0, 53, 55, 1000] {
    var object = original
    object["cells"] = Array(repeating: NSNull(), count: count)
    let bad = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ManualDraft.self, from: bad) }
  }
  for color: Any in [NSNull(), "white"] {
    var object = original
    var cells = originalCells
    cells[4] = color  // The explicitly assigned U center is green.
    object["cells"] = cells
    let bad = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ManualDraft.self, from: bad) }
  }
  var object = original
  object["revision"] = -1
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ManualDraft.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
