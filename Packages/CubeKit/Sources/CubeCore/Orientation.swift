public enum OrientationError: Error { case invalidAxes }

public enum Regrip: UInt8, CaseIterable, Sendable, Codable {
    case yawLeft, yawRight, topToward, bottomToward, rollClockwise, rollCounterclockwise

    public var inverse: Regrip {
        switch self {
        case .yawLeft: .yawRight
        case .yawRight: .yawLeft
        case .topToward: .bottomToward
        case .bottomToward: .topToward
        case .rollClockwise: .rollCounterclockwise
        case .rollCounterclockwise: .rollClockwise
        }
    }

    // Maps old viewer directions to new directions after the physical regrip.
    fileprivate var directions: [Face] {
        switch self {
        case .yawLeft: [.up,.front,.left,.down,.back,.right]
        case .yawRight: [.up,.back,.right,.down,.front,.left]
        case .topToward: [.front,.right,.down,.back,.left,.up]
        case .bottomToward: [.back,.right,.up,.front,.left,.down]
        case .rollClockwise: [.right,.down,.front,.left,.up,.back]
        case .rollCounterclockwise: [.left,.up,.front,.right,.down,.back]
        }
    }
}

extension Face {
    public var opposite: Face { Face.allCases[(Int(rawValue)+3)%6] }

    fileprivate var axis: (Int, Int, Int) {
        switch self {
        case .up: (0,1,0)
        case .right: (1,0,0)
        case .front: (0,0,1)
        case .down: (0,-1,0)
        case .left: (-1,0,0)
        case .back: (0,0,-1)
        }
    }

    fileprivate var topNeighbor: Face { [.back,.up,.up,.front,.up,.up][Int(rawValue)] }
    fileprivate var rightNeighbor: Face { [.right,.back,.right,.right,.front,.left][Int(rawValue)] }
}

/// Proper rotation mapping canonical faces to viewer directions. Never changes puzzle state.
public struct CubeOrientation: Hashable, Sendable, Codable {
    private let directions: [Face]
    private let canonicalDirections: [Face]

    private init(directions: [Face]) {
        self.directions = directions
        var inverse = Face.allCases
        for face in Face.allCases { inverse[Int(directions[Int(face.rawValue)].rawValue)] = face }
        canonicalDirections = inverse
    }

    public static let identity = CubeOrientation(directions: Face.allCases)
    public static let all: [CubeOrientation] = Face.allCases.flatMap { front in
        Face.allCases.compactMap { top in try? CubeOrientation(front: front, top: top) }
    }

    public init(front: Face, top: Face) throws {
        guard front != top, front != top.opposite else { throw OrientationError.invalidAxes }
        let a = top.axis, b = front.axis
        let cross = (a.1*b.2-a.2*b.1, a.2*b.0-a.0*b.2, a.0*b.1-a.1*b.0)
        guard let right = Face.allCases.first(where: { $0.axis == cross }) else { throw OrientationError.invalidAxes }
        var directions = Face.allCases
        for (canonical, view) in [(front,Face.front),(top,Face.up),(right,Face.right)] {
            directions[Int(canonical.rawValue)] = view
            directions[Int(canonical.opposite.rawValue)] = view.opposite
        }
        self.init(directions: directions)
    }

    public func viewFace(for face: Face) -> Face { directions[Int(face.rawValue)] }
    public func canonicalFace(at face: Face) -> Face { canonicalDirections[Int(face.rawValue)] }

    public func regripped(_ operation: Regrip) -> CubeOrientation {
        let transform = operation.directions
        return CubeOrientation(directions: directions.map { transform[Int($0.rawValue)] })
    }

    /// Returns stickers in viewer face order; this is presentation, not canonical normalization.
    public func viewing(_ state: Facelets) -> [Face] { viewing(state.faces) }

    func viewing<T>(_ stickers: [T]) -> [T] {
        precondition(stickers.count == 54)
        var output = stickers
        for face in Face.allCases {
            let target = viewFace(for: face)
            let oldTop = viewFace(for: face.topNeighbor)
            for row in 0..<3 {
                for column in 0..<3 {
                    let r: Int, c: Int
                    if oldTop == target.topNeighbor { (r,c) = (row,column) }
                    else if oldTop == target.rightNeighbor { (r,c) = (column,2-row) }
                    else if oldTop == target.topNeighbor.opposite { (r,c) = (2-row,2-column) }
                    else { (r,c) = (2-column,row) }
                    output[Int(target.rawValue)*9+r*3+c] = stickers[Int(face.rawValue)*9+row*3+column]
                }
            }
        }
        return output
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var directions: [Face] = []
        while !container.isAtEnd {
            guard directions.count < 6 else { throw OrientationError.invalidAxes }
            directions.append(try container.decode(Face.self))
        }
        guard let pose = Self.all.first(where: { $0.directions == directions }) else {
            throw OrientationError.invalidAxes
        }
        self = pose
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for direction in directions { try container.encode(direction) }
    }
}
