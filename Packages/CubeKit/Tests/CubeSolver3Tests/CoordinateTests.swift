import Testing
@testable import CubeSolver3

@Test("V04: all 2187 twist and 2048 flip coordinates round-trip with constrained final digit")
func orientationCoordinates() throws {
    for rank in 0..<2187 {
        let values = try Coordinates.cornerOrientations(rank)
        #expect(values.count == 8)
        #expect(values.allSatisfy { $0 < 3 })
        #expect(values.reduce(0) { $0+Int($1) } % 3 == 0)
        #expect(try Coordinates.twist(values) == rank)
    }
    for rank in 0..<2048 {
        let values = try Coordinates.edgeOrientations(rank)
        #expect(values.count == 12)
        #expect(values.allSatisfy { $0 < 2 })
        #expect(values.reduce(0) { $0+Int($1) } % 2 == 0)
        #expect(try Coordinates.flip(values) == rank)
    }
    #expect(try Coordinates.cornerOrientations(1) == [0,0,0,0,0,0,1,2])
    #expect(try Coordinates.edgeOrientations(1) == [0,0,0,0,0,0,0,0,0,0,1,1])
}

@Test("V04: all 40320 and 24 lexicographic permutations rank and unrank exactly")
func permutationCoordinates() throws {
    for (count,limit) in [(8,40320),(4,24)] {
        var previous: [UInt8]? = nil
        for rank in 0..<limit {
            let values = try Coordinates.unrankPermutation(rank,count:count)
            #expect(values.sorted() == (0..<count).map(UInt8.init))
            #expect(try Coordinates.permutation(values) == rank)
            if let previous { #expect(previous.lexicographicallyPrecedes(values)) }
            previous = values
        }
    }
    #expect(try Coordinates.permutation([0,1,2,3]) == 0)
    #expect(try Coordinates.permutation([3,2,1,0]) == 23)
    #expect(try Coordinates.unrankPermutation(1,count:4) == [0,1,3,2])
}

@Test("V04: all 495 lexicographic slice occupancies round-trip with goal 494")
func sliceCoordinates() throws {
    var previous: [Int]? = nil
    for rank in 0..<495 {
        let positions = try Coordinates.slicePositions(rank)
        #expect(positions.count == 4)
        #expect(Set(positions).count == 4)
        #expect(positions.allSatisfy { (0..<12).contains($0) })
        #expect(positions == positions.sorted())
        if let previous { #expect(previous.lexicographicallyPrecedes(positions)) }
        var nonslice: UInt8 = 0, slice: UInt8 = 8
        let edges: [UInt8] = (0..<12).map { position in
            if positions.contains(position) { defer { slice += 1 }; return slice }
            defer { nonslice += 1 }; return nonslice
        }
        #expect(try Coordinates.slice(edges) == rank)
        previous = positions
    }
    #expect(try Coordinates.slicePositions(0) == [0,1,2,3])
    #expect(try Coordinates.slicePositions(494) == [8,9,10,11])
    #expect(try Coordinates.slice(Array(0...11)) == 494)
}

@Test("V04: reject all coordinate bounds and malformed permutations/orientations")
func malformedCoordinates() {
    for rank in [-1,2187,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.cornerOrientations(rank) } }
    for rank in [-1,2048,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.edgeOrientations(rank) } }
    for rank in [-1,495,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.slicePositions(rank) } }
    for rank in [-1,40320,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.unrankPermutation(rank,count:8) } }
    for rank in [-1,24,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.unrankPermutation(rank,count:4) } }
    for count in [0,1,3,5,9,Int.max] { #expect(throws: CoordinateError.self) { try Coordinates.unrankPermutation(0,count:count) } }
    for values: [UInt8] in [[],[0,0,1,2],[0,1,2,4]] { #expect(throws: CoordinateError.self) { try Coordinates.permutation(values) } }
    for values: [UInt8] in [[],[0,0,0,0,0,0,0,1],[3,0,0,0,0,0,0,0]] { #expect(throws: CoordinateError.self) { try Coordinates.twist(values) } }
    for values: [UInt8] in [[],[0,0,0,0,0,0,0,0,0,0,0,1],[2,0,0,0,0,0,0,0,0,0,0,0]] { #expect(throws: CoordinateError.self) { try Coordinates.flip(values) } }
    for values: [UInt8] in [[],Array(repeating:0,count:12),Array(1...12)] { #expect(throws: CoordinateError.self) { try Coordinates.slice(values) } }
}

@Test("V04: independently computed coordinate fixtures")
func coordinateFixtures() throws {
    #expect(try Coordinates.cornerOrientations(1) == [0,0,0,0,0,0,1,2])
    #expect(try Coordinates.edgeOrientations(1) == [0,0,0,0,0,0,0,0,0,0,1,1])
    #expect(try Coordinates.twist([0,0,0,0,0,0,1,2]) == 1)
    #expect(try Coordinates.flip([0,0,0,0,0,0,0,0,0,0,1,1]) == 1)
    #expect(try Coordinates.permutation([3,2,1,0]) == 23)
    #expect(try Coordinates.unrankPermutation(1,count:4) == [0,1,3,2])
    #expect(try Coordinates.slicePositions(494) == [8,9,10,11])
    #expect(try Coordinates.slice(Array(0...11)) == 494)
}
