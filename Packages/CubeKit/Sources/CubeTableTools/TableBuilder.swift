import CubeCore
import CubeSolver3

package enum GenerationError: Error { case invalidGraph, unreachable, distanceOverflow }

/// Development tooling only. This module is not a dependency of the iPhone application.
package enum TableBuilder {
    package static func distances(left: [UInt16], leftRows: Int, right: [UInt16], rightRows: Int, moves: Int, goalLeft: Int, goalRight: Int) throws -> [UInt16] {
        guard (1...40320).contains(leftRows), (1...495).contains(rightRows), (1...18).contains(moves),
              left.count == leftRows*moves, right.count == rightRows*moves,
              (0..<leftRows).contains(goalLeft), (0..<rightRows).contains(goalRight),
              left.allSatisfy({Int($0)<leftRows}), right.allSatisfy({Int($0)<rightRows}) else {
            throw GenerationError.invalidGraph
        }
        let count = leftRows*rightRows, goal = goalLeft*rightRows+goalRight
        var distances = Array(repeating:UInt16(255),count:count)
        var queue: [Int] = [goal]
        queue.reserveCapacity(count)
        distances[goal] = 0
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            let l = (node/rightRows)*moves, r = (node%rightRows)*moves
            for move in 0..<moves {
                let next = Int(left[l+move])*rightRows+Int(right[r+move])
                if distances[next] == 255 {
                    let distance = distances[node]+1
                    guard distance < 255 else { throw GenerationError.distanceOverflow }
                    distances[next] = distance
                    queue.append(next)
                }
            }
        }
        guard queue.count == count else { throw GenerationError.unreachable }
        return distances
    }

    package static func moveTable(_ id: TableID) throws -> SolverTable {
        guard id.rawValue <= 6 else { throw GenerationError.invalidGraph }
        let moves = id.rawValue <= 3 ? SolverMoves.phaseOne : SolverMoves.phaseTwo
        var values: [UInt16] = []
        values.reserveCapacity(id.count)
        for rank in 0..<id.rows {
            let state = try representative(id,rank:rank)
            for move in moves {
                let moved = state.applying(move)
                let next: Int
                switch id {
                case .twistMove: next = try Coordinates.twist(moved.cornerOrientation)
                case .flipMove: next = try Coordinates.flip(moved.edgeOrientation)
                case .sliceMove: next = try Coordinates.slice(moved.edgePermutation)
                case .cornerPermMove: next = try Coordinates.permutation(moved.cornerPermutation)
                case .edgePermMove: next = try Coordinates.permutation(Array(moved.edgePermutation.prefix(8)))
                case .slicePermMove: next = try Coordinates.permutation(moved.edgePermutation.suffix(4).map {$0-8})
                default: throw GenerationError.invalidGraph
                }
                values.append(UInt16(next))
            }
        }
        return try SolverTable(id:id,values:values)
    }

    private static func representative(_ id: TableID, rank: Int) throws -> Cubies {
        var cp = Array(UInt8(0)...7), co = Array(repeating:UInt8(0),count:8)
        var ep = Array(UInt8(0)...11), eo = Array(repeating:UInt8(0),count:12)
        switch id {
        case .twistMove: co = try Coordinates.cornerOrientations(rank)
        case .flipMove: eo = try Coordinates.edgeOrientations(rank)
        case .sliceMove:
            let positions = try Coordinates.slicePositions(rank)
            var ordinary: UInt8 = 0, slice: UInt8 = 8
            ep = (0..<12).map { position in
                if positions.contains(position) { defer {slice += 1}; return slice }
                defer {ordinary += 1}; return ordinary
            }
        case .cornerPermMove: cp = try Coordinates.unrankPermutation(rank,count:8)
        case .edgePermMove: ep = try Coordinates.unrankPermutation(rank,count:8)+[8,9,10,11]
        case .slicePermMove: ep = try Array(UInt8(0)...7)+Coordinates.unrankPermutation(rank,count:4).map {$0+8}
        default: throw GenerationError.invalidGraph
        }
        return try Cubies(corners:cp,twists:co,edges:ep,flips:eo)
    }

    package static func allTables(completed: (TableID) -> Void = {_ in}) throws -> [SolverTable] {
        var output: [SolverTable] = []
        for id in TableID.allCases.prefix(6) {
            output.append(try moveTable(id))
            completed(id)
        }
        let abstractions: [(TableID, Int, Int, Int)] = [
            (.twistSliceDistance,0,2,494),(.flipSliceDistance,1,2,494),
            (.cornerSlicePermDistance,3,5,0),(.edgeSlicePermDistance,4,5,0)
        ]
        for (id,leftIndex,rightIndex,rightGoal) in abstractions {
            let left = output[leftIndex], right = output[rightIndex]
            let result = try distances(left:left.values,leftRows:left.id.rows,right:right.values,
                                       rightRows:right.id.rows,moves:left.id.columns,goalLeft:0,goalRight:rightGoal)
            output.append(try SolverTable(id:id,values:result))
            completed(id)
        }
        return output
    }
}
