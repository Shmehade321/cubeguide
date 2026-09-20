public enum QuarterTurns: UInt8, CaseIterable, Sendable, Codable {
    case clockwise = 1, half = 2, counterclockwise = 3
}

public struct Move: Equatable, Hashable, Sendable, Codable {
    public let face: Face
    public let turns: QuarterTurns

    public init(face: Face, turns: QuarterTurns) {
        self.face = face
        self.turns = turns
    }

    public var inverse: Move {
        let amount: QuarterTurns
        switch turns {
        case .clockwise: amount = .counterclockwise
        case .half: amount = .half
        case .counterclockwise: amount = .clockwise
        }
        return Move(face: face, turns: amount)
    }

    public var notation: String {
        let suffix: String
        switch turns {
        case .clockwise: suffix = ""
        case .half: suffix = "2"
        case .counterclockwise: suffix = "'"
        }
        return String(decoding: [face.notationByte], as: UTF8.self) + suffix
    }

    /// Bounded notation for a solution of at most 30 face turns.
    public static func parse(_ notation: String) throws -> [Move] {
        guard notation.utf8.prefix(257).count <= 256 else { throw CubeInputError.moveLimit }
        let tokens = notation.split(whereSeparator: \.isWhitespace)
        guard tokens.count <= 30 else { throw CubeInputError.moveLimit }
        return try tokens.map { token in
            let bytes = Array(token.utf8)
            guard let first = bytes.first, let face = Face(notationByte: first), bytes.count <= 2 else {
                throw CubeInputError.moveNotation
            }
            let turns: QuarterTurns
            if bytes.count == 1 { turns = .clockwise }
            else if bytes[1] == 50 { turns = .half }
            else if bytes[1] == 39 { turns = .counterclockwise }
            else { throw CubeInputError.moveNotation }
            return Move(face: face, turns: turns)
        }
    }
}
