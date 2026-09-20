import Foundation
import Testing
@testable import CubeCore

@Test("V02: exactly 24 proper poses with front/top roundtrip and rejected parallel axes")
func poseDomain() throws {
    #expect(Set(CubeOrientation.all).count == 24)
    for front in Face.allCases {
        for top in Face.allCases {
            if front == top || front.opposite == top {
                #expect(throws: OrientationError.self) { try CubeOrientation(front: front, top: top) }
            } else {
                let pose = try CubeOrientation(front: front, top: top)
                #expect(pose.canonicalFace(at: .front) == front)
                #expect(pose.canonicalFace(at: .up) == top)
                #expect(try JSONDecoder().decode(CubeOrientation.self, from: JSONEncoder().encode(pose)) == pose)
            }
        }
    }
}

@Test("V02: regrips have explicit physical directions and inverse identities")
func regripDirections() {
    let expected: [(Regrip,Face,Face)] = [(.yawLeft,.front,.left),(.yawRight,.front,.right),(.topToward,.up,.front),(.bottomToward,.down,.front),(.rollClockwise,.up,.right),(.rollCounterclockwise,.up,.left)]
    for (operation, source, destination) in expected {
        #expect(CubeOrientation.identity.regripped(operation).viewFace(for: source) == destination)
    }
    for pose in CubeOrientation.all {
        for operation in Regrip.allCases {
            let next = pose.regripped(operation)
            #expect(CubeOrientation.all.contains(next))
            #expect(next.regripped(operation.inverse) == pose)
            var result = pose
            for _ in 0..<4 { result = result.regripped(operation) }
            #expect(result == pose)
        }
    }
}

@Test("V02: all 24×18 pose/move conjugations agree on 54 unique stickers")
func moveConjugation() {
    let labels = Array(0..<54)
    for pose in CubeOrientation.all {
        #expect(pose.viewing(labels).sorted() == labels)
        for move in allMoves {
            let canonicalThenView = pose.viewing(CubeMoves.applying(move, to: labels))
            let viewThenMove = CubeMoves.applying(Move(face: pose.viewFace(for: move.face), turns: move.turns), to: pose.viewing(labels))
            #expect(canonicalThenView == viewThenMove)
        }
    }
}

@Test("V02: reject reflected or malformed serialized orientations")
func reflectedPoses() throws {
    for text in ["[]", "[0,1,2,3,4,5,0]", "[0,1,2,3,4,4]", "[0,4,2,3,1,5]", "[6,1,2,3,4,5]"] {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CubeOrientation.self, from: Data(text.utf8)) }
    }
}
