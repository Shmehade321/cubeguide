public enum ValidationIssue: Equatable, Sendable {
    case colorCount(face: Face, actual: Int)
    case center(face: Face, actual: Face)
    case cornerIdentity(position: Int)
    case duplicateCorner(piece: Int)
    case edgeIdentity(position: Int)
    case duplicateEdge(piece: Int)
    case cornerOrientation
    case edgeOrientation
    case permutationParity
}
public struct ValidationIssues: Error, Equatable, Sendable {
    public let items: [ValidationIssue]
}
public struct LegalCube: Equatable, Sendable {
    public let facelets: Facelets
    fileprivate init(facelets: Facelets) { self.facelets = facelets }
}
public enum CubeValidation {
    private static let cornerCells = [[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
    private static let edgeCells = [[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
    private static let corners: [[Face]] = [
        [.up,.right,.front],[.up,.front,.left],[.up,.left,.back],[.up,.back,.right],
        [.down,.front,.right],[.down,.left,.front],[.down,.back,.left],[.down,.right,.back]
    ]
    private static let edges: [[Face]] = [
        [.up,.right],[.up,.front],[.up,.left],[.up,.back],
        [.down,.right],[.down,.front],[.down,.left],[.down,.back],
        [.front,.right],[.front,.left],[.back,.left],[.back,.right]
    ]

    /// Diagnostic order follows the specification: counts, centers, identities, orientations, parity.
    public static func validate(_ state: Facelets) -> Result<LegalCube, ValidationIssues> {
        let faces = state.faces
        func failure(_ issue: ValidationIssue) -> Result<LegalCube, ValidationIssues> {
            .failure(ValidationIssues(items: [issue]))
        }
        for face in Face.allCases {
            let count = faces.filter { $0 == face }.count
            guard count == 9 else { return failure(.colorCount(face: face, actual: count)) }
        }
        for face in Face.allCases {
            let center = faces[Int(face.rawValue)*9+4]
            guard center == face else { return failure(.center(face: face, actual: center)) }
        }
        var cornerPermutation: [Int] = [], cornerOrientation = 0
        for (position, cells) in cornerCells.enumerated() {
            let observed = cells.map { faces[$0] }
            guard let orientation = observed.firstIndex(where: { $0 == .up || $0 == .down }),
                  let piece = corners.firstIndex(where: { identity in
                      (0..<3).allSatisfy { identity[$0] == observed[(orientation+$0)%3] }
                  }) else { return failure(.cornerIdentity(position: position)) }
            guard !cornerPermutation.contains(piece) else { return failure(.duplicateCorner(piece: piece)) }
            cornerPermutation.append(piece)
            cornerOrientation += orientation
        }
        var edgePermutation: [Int] = [], edgeOrientation = 0
        for (position, cells) in edgeCells.enumerated() {
            let observed = cells.map { faces[$0] }
            let direct = edges.firstIndex(of: observed)
            let reversed = edges.firstIndex(of: Array(observed.reversed()))
            guard let piece = direct ?? reversed else { return failure(.edgeIdentity(position: position)) }
            guard !edgePermutation.contains(piece) else { return failure(.duplicateEdge(piece: piece)) }
            edgePermutation.append(piece)
            if direct == nil { edgeOrientation += 1 }
        }
        guard cornerOrientation % 3 == 0 else { return failure(.cornerOrientation) }
        guard edgeOrientation % 2 == 0 else { return failure(.edgeOrientation) }
        guard parity(cornerPermutation) == parity(edgePermutation) else { return failure(.permutationParity) }
        return .success(LegalCube(facelets: state))
    }

    /// Canonical sticker indices related to the current diagnostic, not a guessed repair.
    public static func reviewCells(in state: Facelets) -> [Int] {
        guard case .failure(let issues) = validate(state), let issue = issues.items.first else { return [] }
        let faces = state.faces
        switch issue {
        case .colorCount(let face, _): return faces.indices.filter { faces[$0] == face }
        case .center(let face, _): return [Int(face.rawValue) * 9 + 4]
        case .cornerIdentity(let position): return cornerCells[position].sorted()
        case .edgeIdentity(let position): return edgeCells[position].sorted()
        case .duplicateCorner(let piece):
            return cornerCells.filter { cells in
                let observed = cells.map { faces[$0] }
                return (0..<3).contains { shift in
                    (0..<3).allSatisfy { corners[piece][$0] == observed[($0 + shift) % 3] }
                }
            }.flatMap { $0 }.sorted()
        case .duplicateEdge(let piece):
            return edgeCells.filter { cells in
                let observed = cells.map { faces[$0] }
                return observed == edges[piece] || Array(observed.reversed()) == edges[piece]
            }.flatMap { $0 }.sorted()
        case .cornerOrientation, .edgeOrientation, .permutationParity: return []
        }
    }

    private static func parity(_ permutation: [Int]) -> Int {
        var inversions = 0
        for i in permutation.indices {
            for j in (i+1)..<permutation.count where permutation[i] > permutation[j] { inversions += 1 }
        }
        return inversions % 2
    }
}
