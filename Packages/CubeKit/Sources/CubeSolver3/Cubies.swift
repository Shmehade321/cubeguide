import CubeCore

package struct PhaseTwoCoordinates: Equatable, Sendable { package let corners: Int, edges: Int, slice: Int }

/// Solver-owned cubie operations. Does not call CubeCore's move engine or validation internals.
/// Coordinate-generation states can have unmatched permutation parity; public solving takes LegalCube.
package struct Cubies: Equatable, Sendable {
    package let cornerPermutation: [UInt8], cornerOrientation: [UInt8], edgePermutation: [UInt8], edgeOrientation: [UInt8]
    package static let solved = Cubies(knownCorners:Array(0...7),twists:Array(repeating:0,count:8),edges:Array(0...11),flips:Array(repeating:0,count:12))

    private init(knownCorners: [UInt8], twists: [UInt8], edges: [UInt8], flips: [UInt8]) {
        cornerPermutation=knownCorners;cornerOrientation=twists;edgePermutation=edges;edgeOrientation=flips
    }

    package init(corners: [UInt8], twists: [UInt8], edges: [UInt8], flips: [UInt8]) throws {
        guard corners.count == 8, edges.count == 12, edges.sorted() == Array(UInt8(0)...11) else {
            throw CoordinateError.invalidValues
        }
        _ = try Coordinates.permutation(corners)
        _ = try Coordinates.twist(twists)
        _ = try Coordinates.flip(flips)
        self.init(knownCorners:corners,twists:twists,edges:edges,flips:flips)
    }

    private static let cornerSlots = [[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
    private static let edgeSlots = [[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
    private static let cornerColors: [[Face]] = [
        [.up,.right,.front],[.up,.front,.left],[.up,.left,.back],[.up,.back,.right],
        [.down,.front,.right],[.down,.left,.front],[.down,.back,.left],[.down,.right,.back]
    ]
    private static let edgeColors: [[Face]] = [
        [.up,.right],[.up,.front],[.up,.left],[.up,.back],
        [.down,.right],[.down,.front],[.down,.left],[.down,.back],
        [.front,.right],[.front,.left],[.back,.left],[.back,.right]
    ]

    package init(cube: LegalCube) throws {
        let faces = cube.facelets.faces
        func decode(slots: [[Int]], colors: [[Face]]) throws -> ([UInt8],[UInt8]) {
            var pieces: [UInt8] = [], orientations: [UInt8] = []
            for slot in slots {
                let observed = slot.map { faces[$0] }
                var found: (UInt8,UInt8)?
                for piece in colors.indices {
                    for rotation in slot.indices {
                        if slot.indices.allSatisfy({ observed[($0+rotation)%slot.count] == colors[piece][$0] }) {
                            found = (UInt8(piece),UInt8(rotation))
                        }
                    }
                }
                guard let found else { throw CoordinateError.invalidValues }
                pieces.append(found.0);orientations.append(found.1)
            }
            return (pieces,orientations)
        }
        let corners = try decode(slots:Self.cornerSlots,colors:Self.cornerColors)
        let edges = try decode(slots:Self.edgeSlots,colors:Self.edgeColors)
        try self.init(corners:corners.0,twists:corners.1,edges:edges.0,flips:edges.1)
    }

    // Destination→source piece permutations and orientation increments, U,R,F,D,L,B.
    // Authored from the written cubie convention; not generated from CubeCore permutations.
    private static let cornerMoves: [[UInt8]] = [
        [3,0,1,2,4,5,6,7], [4,1,2,0,7,5,6,3], [1,5,2,3,0,4,6,7],
        [0,1,2,3,5,6,7,4], [0,2,6,3,4,1,5,7], [0,1,3,7,4,5,2,6]
    ]
    private static let twistMoves: [[UInt8]] = [
        [0,0,0,0,0,0,0,0], [2,0,0,1,1,0,0,2], [1,2,0,0,2,1,0,0],
        [0,0,0,0,0,0,0,0], [0,1,2,0,0,2,1,0], [0,0,1,2,0,0,2,1]
    ]
    private static let edgeMoves: [[UInt8]] = [
        [3,0,1,2,4,5,6,7,8,9,10,11], [8,1,2,3,11,5,6,7,4,9,10,0],
        [0,9,2,3,4,8,6,7,1,5,10,11], [0,1,2,3,5,6,7,4,8,9,10,11],
        [0,1,10,3,4,5,9,7,8,2,6,11], [0,1,2,11,4,5,6,10,8,9,3,7]
    ]
    private static let flipMoves: [[UInt8]] = [
        [0,0,0,0,0,0,0,0,0,0,0,0], [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,1,0,0,0,1,0,0,1,1,0,0], [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0], [0,0,0,1,0,0,0,1,0,0,1,1]
    ]

    package func applying(_ move: Move) -> Cubies {
        var state = self
        let face = Int(move.face.rawValue)
        let cp = Self.cornerMoves[face], co = Self.twistMoves[face]
        let ep = Self.edgeMoves[face], eo = Self.flipMoves[face]
        for _ in 0..<move.turns.rawValue {
            state = Cubies(
                knownCorners: cp.map { state.cornerPermutation[Int($0)] },
                twists: cp.indices.map { (state.cornerOrientation[Int(cp[$0])]+co[$0])%3 },
                edges: ep.map { state.edgePermutation[Int($0)] },
                flips: ep.indices.map { (state.edgeOrientation[Int(ep[$0])]+eo[$0])%2 }
            )
        }
        return state
    }

    package func facelets() throws -> Facelets {
        var faces = Facelets.solved.faces
        for position in 0..<8 {
            for sticker in 0..<3 {
                let cell = Self.cornerSlots[position][(sticker+Int(cornerOrientation[position]))%3]
                faces[cell] = Self.cornerColors[Int(cornerPermutation[position])][sticker]
            }
        }
        for position in 0..<12 {
            for sticker in 0..<2 {
                let cell = Self.edgeSlots[position][(sticker+Int(edgeOrientation[position]))%2]
                faces[cell] = Self.edgeColors[Int(edgePermutation[position])][sticker]
            }
        }
        return try Facelets(faces)
    }

    package func phaseTwoCoordinates() throws -> PhaseTwoCoordinates {
        guard cornerOrientation.allSatisfy({$0 == 0}), edgeOrientation.allSatisfy({$0 == 0}),
              edgePermutation.prefix(8).allSatisfy({$0 < 8}), edgePermutation.suffix(4).allSatisfy({$0 >= 8}) else {
            throw CoordinateError.invalidValues
        }
        return try PhaseTwoCoordinates(corners:Coordinates.permutation(cornerPermutation),
                                       edges:Coordinates.permutation(Array(edgePermutation.prefix(8))),
                                       slice:Coordinates.permutation(edgePermutation.suffix(4).map {$0-8}))
    }
}
