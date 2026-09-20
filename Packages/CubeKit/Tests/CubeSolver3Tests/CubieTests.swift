import Testing
import CubeCore
@testable import CubeSolver3

private let moves = Face.allCases.flatMap { face in QuarterTurns.allCases.map { Move(face:face,turns:$0) } }

@Test("V04: cubie conversion and all independent cubie moves agree with facelet replay")
func cubieMoves() throws {
    var facelets = Facelets.solved
    var cubies = Cubies.solved
    #expect(try cubies.facelets() == .solved)
    for step in 0..<120 {
        for move in moves {
            #expect(try cubies.applying(move).facelets() == facelets.applying([move]))
            #expect(cubies.applying(move).applying(move.inverse) == cubies)
        }
        let move = moves[(step*13+step/5)%18]
        facelets = facelets.applying([move])
        cubies = cubies.applying(move)
        let legal = try CubeValidation.validate(facelets).get()
        #expect(try Cubies(cube: legal) == cubies)
    }
}

@Test("V04: phase-two coordinates reject orientation or slice-membership violations")
func phaseTwoDomain() throws {
    let solved = try Cubies.solved.phaseTwoCoordinates()
    #expect(solved == PhaseTwoCoordinates(corners:0,edges:0,slice:0))
    for face in [Face.right,.front,.left,.back] {
        #expect(throws: CoordinateError.self) { try Cubies.solved.applying(Move(face:face,turns:.clockwise)).phaseTwoCoordinates() }
    }
    for move in moves where move.face == .up || move.face == .down || move.turns == .half {
        let state = Cubies.solved.applying(move)
        let coordinate = try state.phaseTwoCoordinates()
        #expect((0..<40320).contains(coordinate.corners))
        #expect((0..<40320).contains(coordinate.edges))
        #expect((0..<24).contains(coordinate.slice))
    }
}

@Test("V04: independently specified R cubie transition")
func rCubieFixture() throws {
    let state = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    let legal = try CubeValidation.validate(state).get()
    #expect(try Cubies(cube:legal).facelets() == state)
    #expect(try Cubies(cube:legal).cornerPermutation == [4,1,2,0,7,5,6,3])
    let r = Cubies.solved.applying(Move(face:.right,turns:.clockwise))
    #expect(r.cornerPermutation == [4,1,2,0,7,5,6,3])
    #expect(r.cornerOrientation == [2,0,0,1,1,0,0,2])
    #expect(r.edgePermutation == [8,1,2,3,11,5,6,7,4,9,10,0])
    #expect(r.edgeOrientation == Array(repeating:0,count:12))
}

@Test("V04: malformed cubie arrays cannot enter coordinate table generation")
func malformedCubies() {
    #expect(throws: CoordinateError.self) {
        try Cubies(corners:[],twists:[],edges:[],flips:[])
    }
    #expect(throws: CoordinateError.self) {
        try Cubies(corners:Array(0...7),twists:Array(repeating:0,count:8),edges:Array(repeating:0,count:12),flips:Array(repeating:0,count:12))
    }
}
