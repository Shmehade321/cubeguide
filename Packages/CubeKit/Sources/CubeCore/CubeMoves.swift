/// Explicit facelet cycles, independent of the solver's cubie-coordinate operations.
/// Each four-cycle lists source→destination in clockwise order viewed from outside.
enum CubeMoves {
    private static let strips: [[[Int]]] = [
        [[18,36,45,9], [19,37,46,10], [20,38,47,11]],       // U
        [[20,2,51,29], [23,5,48,32], [26,8,45,35]],        // R
        [[6,9,29,44], [7,12,28,41], [8,15,27,38]],         // F
        [[24,15,51,42], [25,16,52,43], [26,17,53,44]],     // D
        [[18,27,53,0], [21,30,50,3], [24,33,47,6]],        // L
        [[0,42,35,11], [1,39,34,14], [2,36,33,17]]         // B
    ]

    static func applying<T>(_ move: Move, to values: [T]) -> [T] {
        // Internal callers operate on validated 54-element states or fixed test labels.
        precondition(values.count == 54)
        var output = values
        let offset = Int(move.face.rawValue) * 9
        let cycles = [[0,2,8,6], [1,5,7,3]].map { $0.map { $0 + offset } }
            + strips[Int(move.face.rawValue)]
        let shift = Int(move.turns.rawValue)
        for cycle in cycles {
            for index in 0..<4 { output[cycle[(index + shift) % 4]] = values[cycle[index]] }
        }
        return output
    }
}
