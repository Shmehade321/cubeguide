import Testing

@testable import CubeCore

@Test(
  "R03: review marks observed colors and inconsistent centers without guessing missing stickers")
func reviewCountsAndCenters() throws {
  var faces = Facelets.solved.faces
  faces[0] = .right
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == Array(1...8))
  faces = Facelets.solved.faces
  faces.swapAt(4, 13)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [4])
}

@Test("R03: impossible pieces identify their actual canonical sticker positions")
func reviewImpossiblePieces() throws {
  for cells in cornerCells {
    var faces = Facelets.solved.faces
    faces.swapAt(cells[1], cells[2])
    #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == cells.sorted())
  }
  var faces = Facelets.solved.faces
  faces.swapAt(10, 28)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [5, 10])
}

@Test("R03: duplicated pieces mark both occurrences, not their expected home locations")
func reviewDuplicatePieces() throws {
  var faces = Facelets.solved.faces
  faces.swapAt(10, 43)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [3, 5, 10, 37])
  for cells in [[5, 10], [3, 37]] {
    shiftedPiece(cells, by: 1, in: &faces)
    #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [3, 5, 10, 37])
  }
  faces = Facelets.solved.faces
  faces[9] = .front
  faces[20] = .left
  faces[36] = .back
  faces[47] = .right
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [6, 8, 9, 18, 20, 38])
  for cells in [[8, 9, 20], [6, 18, 38]] {
    for _ in 0..<2 {
      shiftedPiece(cells, by: 1, in: &faces)
      #expect(CubeValidation.reviewCells(in: try Facelets(faces)) == [6, 8, 9, 18, 20, 38])
    }
  }
}

@Test("R03: global orientation/parity errors and valid states do not invent a faulty piece")
func reviewCannotLocalizeGlobalErrors() throws {
  #expect(CubeValidation.reviewCells(in: .solved).isEmpty)
  #expect(
    CubeValidation.reviewCells(in: .solved.applying([Move(face: .right, turns: .clockwise)]))
      .isEmpty)
  var faces = Facelets.solved.faces
  shiftedPiece(cornerCells[0], by: 1, in: &faces)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)).isEmpty)
  faces = Facelets.solved.faces
  shiftedPiece(edgeCells[0], by: 1, in: &faces)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)).isEmpty)
  faces = Facelets.solved.faces
  swappedPieces(edgeCells[0], edgeCells[1], in: &faces)
  #expect(CubeValidation.reviewCells(in: try Facelets(faces)).isEmpty)
}
