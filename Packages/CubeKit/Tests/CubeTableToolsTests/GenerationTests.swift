import Testing
import CubeSolver3
@testable import CubeTableTools

@Test("V04: product abstraction BFS computes exact small-graph distances and nonzero goals")
func smallDistances() throws {
    let left: [UInt16] = [1,2,0,2,0,1,0,1,2]
    let right: [UInt16] = [0,0,1,1,1,0]
    #expect(try TableBuilder.distances(left:left,leftRows:3,right:right,rightRows:2,moves:3,goalLeft:0,goalRight:0) == [0,1,1,2,1,2])
    #expect(try TableBuilder.distances(left:left,leftRows:3,right:right,rightRows:2,moves:3,goalLeft:2,goalRight:1) == [2,1,2,1,1,0])
}

@Test("V04: BFS refuses malformed, unreachable and overflowing abstractions")
func invalidGraphs() {
    #expect(throws: GenerationError.self) { try TableBuilder.distances(left:[],leftRows:Int.max,right:[],rightRows:2,moves:1,goalLeft:0,goalRight:0) }
    #expect(throws: GenerationError.self) { try TableBuilder.distances(left:[0,1],leftRows:2,right:[0],rightRows:1,moves:1,goalLeft:0,goalRight:0) }
    #expect(throws: GenerationError.self) { try TableBuilder.distances(left:[1],leftRows:1,right:[0],rightRows:1,moves:1,goalLeft:0,goalRight:0) }
    #expect(throws: GenerationError.self) { try TableBuilder.distances(left:[0],leftRows:1,right:[0],rightRows:1,moves:1,goalLeft:1,goalRight:0) }
    let cycle: [UInt16] = (0..<256).map { UInt16(($0+1)%256) }
    #expect(throws: GenerationError.self) { try TableBuilder.distances(left:cycle,leftRows:256,right:[0],rightRows:1,moves:1,goalLeft:0,goalRight:0) }
}

@Test("V04: generated move columns follow phase order and independent solved fixtures")
func generatedTransitions() throws {
    let slice = try TableBuilder.moveTable(.slicePermMove)
    #expect(slice.values.count == 240)
    #expect(Array(slice.values.prefix(10)) == [0,0,0,0,0,0,21,6,2,1])
    let twist = try TableBuilder.moveTable(.twistMove)
    #expect(twist.values.count == 2187*18)
    #expect(Array(twist.values.prefix(18)) == [0,0,0,1494,0,1494,1236,0,1236,0,0,0,412,0,412,137,0,137])
}

@Test("V04: full generation covers all ten domains with solved distances and declared payload budget")
func allGeneratedTables() throws {
    let tables = try TableBuilder.allTables()
    try #require(tables.count == 10)
    #expect(tables.map(\.id) == TableID.allCases)
    #expect(tables.reduce(0) {$0+$1.id.count*$1.id.width} == 5_815_005)
    for table in tables {
        #expect(table.values.count == table.id.count)
        if table.id.rawValue > 6 {
            let goal = table.id == .twistSliceDistance || table.id == .flipSliceDistance ? 494 : 0
            #expect(table.values[goal] == 0)
            #expect(table.values.filter {$0 == 0}.count == 1)
            #expect(table.values.allSatisfy {$0 < 255})
        }
    }
}
