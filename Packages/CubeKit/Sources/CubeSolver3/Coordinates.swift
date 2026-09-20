public enum CoordinateError: Error { case outOfRange, invalidValues }

/// Conventional unsymmetrized coordinates. Solved UD-slice occupancy has rank 494.
package enum Coordinates {
    package static func cornerOrientations(_ rank: Int) throws -> [UInt8] {
        try decodeOrientation(rank, count: 8, radix: 3, limit: 2187)
    }
    package static func edgeOrientations(_ rank: Int) throws -> [UInt8] {
        try decodeOrientation(rank, count: 12, radix: 2, limit: 2048)
    }
    package static func twist(_ values: [UInt8]) throws -> Int {
        try encodeOrientation(values, count: 8, radix: 3)
    }
    package static func flip(_ values: [UInt8]) throws -> Int {
        try encodeOrientation(values, count: 12, radix: 2)
    }

    private static func decodeOrientation(_ rank: Int, count: Int, radix: Int, limit: Int) throws -> [UInt8] {
        guard (0..<limit).contains(rank) else { throw CoordinateError.outOfRange }
        var value = rank, sum = 0
        var result = Array(repeating: UInt8(0), count: count)
        for index in (0..<(count-1)).reversed() {
            let digit = value % radix
            result[index] = UInt8(digit)
            sum += digit
            value /= radix
        }
        result[count-1] = UInt8((radix-sum%radix)%radix)
        return result
    }

    private static func encodeOrientation(_ values: [UInt8], count: Int, radix: Int) throws -> Int {
        guard values.count == count, values.allSatisfy({ Int($0) < radix }),
              values.reduce(0, { $0+Int($1) }) % radix == 0 else { throw CoordinateError.invalidValues }
        return values.prefix(count-1).reduce(0) { $0*radix+Int($1) }
    }

    private static let factorials = [1,1,2,6,24,120,720,5040,40320]

    package static func permutation(_ values: [UInt8]) throws -> Int {
        let count = values.count
        guard count == 4 || count == 8,
              values.sorted() == (0..<count).map(UInt8.init) else { throw CoordinateError.invalidValues }
        var rank = 0
        for index in values.indices {
            let smaller = values[(index+1)..<count].filter { $0 < values[index] }.count
            rank = rank * (count-index) + smaller
        }
        return rank
    }

    package static func unrankPermutation(_ rank: Int, count: Int) throws -> [UInt8] {
        guard count == 4 || count == 8 else { throw CoordinateError.outOfRange }
        guard (0..<factorials[count]).contains(rank) else { throw CoordinateError.outOfRange }
        var pool = (0..<count).map(UInt8.init), value = rank
        var result: [UInt8] = []
        for index in 0..<count {
            let divisor = factorials[count-index-1]
            result.append(pool.remove(at: value/divisor))
            value %= divisor
        }
        return result
    }

    package static func slice(_ values: [UInt8]) throws -> Int {
        guard values.count == 12, values.sorted() == Array(UInt8(0)...11) else { throw CoordinateError.invalidValues }
        let positions = values.indices.filter { values[$0] >= 8 }
        var rank = 0, previous = -1
        for (index, position) in positions.enumerated() {
            for candidate in (previous+1)..<position { rank += choose(11-candidate, 3-index) }
            previous = position
        }
        return rank
    }

    package static func slicePositions(_ rank: Int) throws -> [Int] {
        guard (0..<495).contains(rank) else { throw CoordinateError.outOfRange }
        var result: [Int] = [], candidate = 0, remaining = rank
        for index in 0..<4 {
            while candidate < 12 {
                let block = choose(11-candidate, 3-index)
                if remaining < block { result.append(candidate); candidate += 1; break }
                remaining -= block
                candidate += 1
            }
        }
        return result
    }

    private static func choose(_ n: Int, _ k: Int) -> Int {
        guard k > 0 else { return 1 }
        guard n >= k else { return 0 }
        return (1...k).reduce(1) { $0 * (n-k+$1) / $1 }
    }
}
