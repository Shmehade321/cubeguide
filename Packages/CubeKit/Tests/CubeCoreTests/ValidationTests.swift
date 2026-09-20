import Testing
@testable import CubeCore

// Manually indexed from the specification's outside-view U,R,F,D,L,B grids.
let cornerCells = [[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
let edgeCells = [[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]

func shiftedPiece(_ cells: [Int], by amount: Int, in faces: inout [Face]) {
    let old = cells.map { faces[$0] }
    for i in cells.indices { faces[cells[(i+amount)%cells.count]] = old[i] }
}
func swappedPieces(_ first: [Int], _ second: [Int], in faces: inout [Face]) {
    for i in first.indices { faces.swapAt(first[i], second[i]) }
}
func issue(_ faces: [Face]) throws -> ValidationIssue? {
    switch CubeValidation.validate(try Facelets(faces)) {
    case .success: nil
    case .failure(let issues): issues.items.first
    }
}

@Test("V03: solved and every independent golden scramble is accepted")
func legalStates() throws {
    #expect(try CubeValidation.validate(.solved).get().facelets == .solved)
    var labels = Array(0..<54)
    for step in 0..<240 {
        let permutation = goldenQuarterTurns[(step*17+step/7)%6]
        let old = labels
        for i in labels.indices { labels[permutation[i]] = old[i] }
        let faces = labels.map { Face.allCases[$0/9] }
        #expect(try issue(faces) == nil)
    }
}

@Test("V03: color count and center diagnostics precede piece diagnostics")
func basicValidation() throws {
    var faces = Facelets.solved.faces
    faces[0] = .right
    #expect(try issue(faces) == .colorCount(face: .up, actual: 8))
    faces = Facelets.solved.faces
    faces.swapAt(4,13)
    #expect(try issue(faces) == .center(face: .up, actual: .right))
}

@Test("V03: every isolated corner twist rejected and balanced twists accepted")
func cornerTwists() throws {
    for corner in cornerCells.indices {
        for amount in [1,2] {
            var faces = Facelets.solved.faces
            shiftedPiece(cornerCells[corner],by:amount,in:&faces)
            #expect(try issue(faces) == .cornerOrientation)
            shiftedPiece(cornerCells[(corner+1)%8],by:3-amount,in:&faces)
            #expect(try issue(faces) == nil)
        }
    }
}

@Test("V03: every isolated edge flip rejected and paired flips accepted")
func edgeFlips() throws {
    for edge in edgeCells.indices {
        var faces = Facelets.solved.faces
        shiftedPiece(edgeCells[edge],by:1,in:&faces)
        #expect(try issue(faces) == .edgeOrientation)
        shiftedPiece(edgeCells[(edge+1)%12],by:1,in:&faces)
        #expect(try issue(faces) == nil)
    }
}

@Test("V03: every isolated piece transposition rejected, matched parity accepted")
func permutationParity() throws {
    for pieces in [cornerCells,edgeCells] {
        for a in pieces.indices {
            for b in (a+1)..<pieces.count {
                var faces = Facelets.solved.faces
                swappedPieces(pieces[a],pieces[b],in:&faces)
                #expect(try issue(faces) == .permutationParity)
                let other = pieces.count == 8 ? edgeCells : cornerCells
                swappedPieces(other[0],other[1],in:&faces)
                #expect(try issue(faces) == nil)
            }
        }
    }
}

@Test("V03: mirrored corners and impossible edges rejected without misleading parity diagnosis")
func impossiblePieces() throws {
    for cells in cornerCells {
        var faces = Facelets.solved.faces
        faces.swapAt(cells[1],cells[2])
        #expect(try issue(faces) == .cornerIdentity(position: cornerCells.firstIndex(of: cells)!))
    }
    var faces = Facelets.solved.faces
    faces.swapAt(10,43) // UR becomes UL duplicate; DL becomes DR duplicate while counts stay balanced.
    #expect(try issue(faces) == .duplicateEdge(piece: 2))
    faces = Facelets.solved.faces
    faces.swapAt(10,28) // UR becomes UD, which is not an edge.
    #expect(try issue(faces) == .edgeIdentity(position: 0))
}

@Test("V03: balanced duplicate corner inventory is rejected")
func duplicateCorners() throws {
    var faces = Facelets.solved.faces
    faces[9] = .front; faces[20] = .left // URF→UFL
    faces[36] = .back; faces[47] = .right // ULB→UBR; global counts preserved.
    #expect(try issue(faces) == .duplicateCorner(piece: 1))
}
