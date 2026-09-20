import Foundation

public enum CubeInputError: Error, Equatable, Sendable {
    case faceletCount
    case faceletLabel
    case moveNotation
    case moveLimit
}

/// A structurally valid canonical 54-facelet arrangement. Reachability is checked separately.
public struct Facelets: Equatable, Hashable, Sendable, Codable {
    public let faces: [Face]

    public init(_ faces: [Face]) throws {
        guard faces.count == 54 else { throw CubeInputError.faceletCount }
        self.faces = faces
    }

    public init(notation: String) throws {
        let bytes = Array(notation.utf8.prefix(55))
        guard bytes.count == 54 else { throw CubeInputError.faceletCount }
        self.faces = try bytes.map { byte in
            guard let face = Face(notationByte: byte) else { throw CubeInputError.faceletLabel }
            return face
        }
    }

    private init(knownFaces: [Face]) { faces = knownFaces }

    public func applying(_ moves: [Move]) -> Facelets {
        Facelets(knownFaces: moves.reduce(faces) { CubeMoves.applying($1, to: $0) })
    }

    public var notation: String { String(decoding: faces.map(\.notationByte), as: UTF8.self) }

    public static let solved = Facelets(knownFaces: Face.allCases.flatMap { Array(repeating: $0, count: 9) })

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(notation: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}

extension Face {
    var notationByte: UInt8 {
        switch self {
        case .up: 85
        case .right: 82
        case .front: 70
        case .down: 68
        case .left: 76
        case .back: 66
        }
    }

    init?(notationByte: UInt8) {
        switch notationByte {
        case 85: self = .up
        case 82: self = .right
        case 70: self = .front
        case 68: self = .down
        case 76: self = .left
        case 66: self = .back
        default: return nil
        }
    }
}
