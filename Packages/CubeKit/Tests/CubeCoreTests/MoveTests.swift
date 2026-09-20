import Testing
@testable import CubeCore

let allMoves = Face.allCases.flatMap { face in QuarterTurns.allCases.map { Move(face: face, turns: $0) } }

@Test("V01: six clockwise permutations match independently generated 54-sticker golden destinations", arguments: Face.allCases)
func quarterTurnDestinations(face: Face) {
    let move = Move(face: face, turns: .clockwise)
    let labels = Array(0..<54)
    let actual = CubeMoves.applying(move, to: labels)
    let golden = goldenQuarterTurns[Int(face.rawValue)]
    for source in 0..<54 { #expect(actual[golden[source]] == source) }
}

@Test("V01: all 18 moves preserve labels and fixed centers, invert and have correct powers", arguments: allMoves)
func moveIdentities(move: Move) {
    let labels = Array(0..<54)
    let after = CubeMoves.applying(move, to: labels)
    #expect(after.sorted() == labels)
    for center in [4,13,22,31,40,49] { #expect(after[center] == center) }
    #expect(CubeMoves.applying(move.inverse, to: after) == labels)
    var repeated = labels
    for _ in 0..<4 { repeated = CubeMoves.applying(move, to: repeated) }
    #expect(repeated == labels)
    if move.turns == .half { #expect(CubeMoves.applying(move, to: after) == labels) }
    var fromQuarter = labels
    for _ in 0..<move.turns.rawValue {
        fromQuarter = CubeMoves.applying(Move(face: move.face, turns: .clockwise), to: fromQuarter)
    }
    #expect(fromQuarter == after)
}

@Test("V01: opposite turns commute, adjacent turns do not")
func commutation() {
    let labels = Array(0..<54)
    func apply(_ first: Face, _ second: Face) -> [Int] {
        CubeMoves.applying(Move(face: second, turns: .clockwise), to: CubeMoves.applying(Move(face: first, turns: .clockwise), to: labels))
    }
    for (a,b) in [(Face.up,Face.down),(Face.right,Face.left),(Face.front,Face.back)] { #expect(apply(a,b) == apply(b,a)) }
    for (a,b) in [(Face.up,Face.front),(Face.right,Face.front),(Face.left,Face.down)] { #expect(apply(a,b) != apply(b,a)) }
}

@Test("V01: public application matches fixed R scramble and inverse")
func publicMoveApplication() throws {
    let r = Move(face: .right, turns: .clockwise)
    // R clockwise: F right→U right, D right→F right, B left reversed→D right, U right reversed→B left.
    let after = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    #expect(Facelets.solved.applying([r]) == after)
    #expect(after.applying([r.inverse]) == .solved)
}

@Test("V01: fixed practice sequence matches independent unique-label composition")
func sequenceOracle() throws {
    let moves = try Move.parse("R U R' U' F2")
    var expected = Array(0..<54)
    var actual = expected
    for move in moves {
        for _ in 0..<move.turns.rawValue {
            let before = expected
            for source in 0..<54 { expected[goldenQuarterTurns[Int(move.face.rawValue)][source]] = before[source] }
        }
        actual = CubeMoves.applying(move, to: actual)
    }
    #expect(actual == expected)
    #expect(actual != Array(0..<54))
}
