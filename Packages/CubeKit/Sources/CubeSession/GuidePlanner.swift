import CubeCore

public enum GuidePlanningError: Error { case invalidActionID, invalidState }
public struct ActionID: Equatable, Hashable, Sendable, Codable {
  public let sessionRevision: UInt64
  public let moveIndex: Int
  public let actionIndex: Int
  public init(sessionRevision: UInt64, moveIndex: Int, actionIndex: Int) throws {
    guard (0..<30).contains(moveIndex), (0...2).contains(actionIndex) else {
      throw GuidePlanningError.invalidActionID
    }
    self.sessionRevision = sessionRevision
    self.moveIndex = moveIndex
    self.actionIndex = actionIndex
  }
  private enum CodingKeys: String, CodingKey { case sessionRevision, moveIndex, actionIndex }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      sessionRevision: values.decode(UInt64.self, forKey: .sessionRevision),
      moveIndex: values.decode(Int.self, forKey: .moveIndex),
      actionIndex: values.decode(Int.self, forKey: .actionIndex))
  }
}
public enum GuideOperation: Equatable, Sendable {
  case regrip(Regrip)
  case turn(Move)
}
public struct GuideAction: Equatable, Sendable {
  public let id: ActionID
  public let operation: GuideOperation
  public let before: Facelets
  public let after: Facelets
  public let fromPose: CubeOrientation
  public let toPose: CubeOrientation
  public var demonstratedMove: Move? {
    guard case .turn(let move) = operation else { return nil }
    return Move(face: .front, turns: move.turns)
  }
}
public enum GuidePlanner {
  public static func actions(
    for move: Move, at pose: CubeOrientation, state: Facelets,
    sessionRevision: UInt64, moveIndex: Int
  ) throws -> [GuideAction] {
    _ = try ActionID(sessionRevision: sessionRevision, moveIndex: moveIndex, actionIndex: 0)
    let path = try regrips(toFront: move.face, from: pose)
    var current = pose
    var actions: [GuideAction] = []
    for operation in path {
      let after = current.regripped(operation)
      let id = try ActionID(
        sessionRevision: sessionRevision, moveIndex: moveIndex,
        actionIndex: actions.count)
      actions.append(
        GuideAction(
          id: id, operation: .regrip(operation), before: state,
          after: state, fromPose: current, toPose: after))
      current = after
    }
    let id = try ActionID(
      sessionRevision: sessionRevision, moveIndex: moveIndex,
      actionIndex: actions.count)
    actions.append(
      GuideAction(
        id: id, operation: .turn(move), before: state,
        after: state.applying([move]), fromPose: current, toPose: current))
    return actions
  }

  private static func regrips(toFront face: Face, from pose: CubeOrientation) throws -> [Regrip] {
    if pose.viewFace(for: face) == .front { return [] }
    var queue: [(CubeOrientation, [Regrip])] = [(pose, [])]
    var seen: Set<CubeOrientation> = [pose]
    var index = 0
    while index < queue.count {
      let (current, path) = queue[index]
      index += 1
      for operation in Regrip.allCases {
        let next = current.regripped(operation)
        guard seen.insert(next).inserted else { continue }
        let steps = path + [operation]
        if next.viewFace(for: face) == .front { return steps }
        queue.append((next, steps))
      }
    }
    throw GuidePlanningError.invalidState
  }
}
