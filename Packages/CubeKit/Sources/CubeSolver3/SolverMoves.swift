import CubeCore

package enum SolverMoves {
    package static let phaseOne = Face.allCases.flatMap { face in
        QuarterTurns.allCases.map { Move(face:face,turns:$0) }
    }
    package static let phaseTwo = [Face.up,.down].flatMap { face in
        QuarterTurns.allCases.map { Move(face:face,turns:$0) }
    } + [Face.right,.front,.left,.back].map { Move(face:$0,turns:.half) }
}
