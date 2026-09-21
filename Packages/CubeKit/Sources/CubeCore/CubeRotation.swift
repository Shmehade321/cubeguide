/// Exact presentation rotation about an outward-facing cube axis.
/// Its angle describes animation only and never advances a physical guide step.
public struct CubeRotation: Equatable, Sendable {
  public let axis: Face
  public let turns: QuarterTurns
  private let orientation: CubeOrientation
  public init(axis: Face, turns: QuarterTurns) {
    self.axis = axis
    self.turns = turns
    let step: Regrip
    switch axis {
    case .up: step = .yawLeft
    case .down: step = .yawRight
    case .right: step = .bottomToward
    case .left: step = .topToward
    case .front: step = .rollClockwise
    case .back: step = .rollCounterclockwise
    }
    var result = CubeOrientation.identity
    for _ in 0..<Int(turns.rawValue) { result = result.regripped(step) }
    orientation = result
  }
  public init(regrip: Regrip) {
    let axis: Face
    switch regrip {
    case .yawLeft: axis = .up
    case .yawRight: axis = .down
    case .topToward: axis = .left
    case .bottomToward: axis = .right
    case .rollClockwise: axis = .front
    case .rollCounterclockwise: axis = .back
    }
    self.init(axis: axis, turns: .clockwise)
  }
  /// Multiply by pi/2 to obtain a right-handed animation angle.
  public var signedQuarterTurns: Int {
    switch turns {
    case .clockwise: -1
    case .half: -2
    case .counterclockwise: 1
    }
  }
  public func applying(to point: CubePosition) -> CubePosition { point.viewed(at: orientation) }
  public func applying(to sticker: CubeStickerPlacement) -> CubeStickerPlacement {
    sticker.viewed(at: orientation)
  }
}
