import CubeCore
import CubeScan

/// A fictional, editable example; never a statement about the user's physical cube.
public enum PracticeExample {
  public static func draft() throws -> ManualDraft {
    let palette = try CenterPalette([.white, .red, .green, .yellow, .orange, .blue])
    let faces = Facelets.solved.applying(try Move.parse("R U R' U' F2"))
    var draft = ManualDraft(palette: palette)
    for face in Face.allCases {
      for cell in 0..<9 where cell != 4 {
        let canonical = faces.faces[Int(face.rawValue) * 9 + cell]
        draft = try draft.setting(face: face, row: cell / 3, column: cell % 3,
          color: palette.colors[Int(canonical.rawValue)])
      }
    }
    return draft
  }
}
