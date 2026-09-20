import CubeCore

/// Immutable proposed progress. Only a successful matching save may make it the session's durable progress.
public struct GuideProgress: Equatable, Sendable {
  public let plan: VerifiedPlan
  public let revision: UInt64
  public let actions: [GuideAction]
  public let acknowledgedActions: Int
  public var pending: GuideAction? { isComplete ? nil : actions[acknowledgedActions] }
  public var state: Facelets {
    acknowledgedActions == 0 ? plan.original : actions[acknowledgedActions - 1].after
  }
  public var pose: CubeOrientation {
    acknowledgedActions == 0 ? .identity : actions[acknowledgedActions - 1].toPose
  }
  public var moveIndex: Int {
    actions.prefix(acknowledgedActions).reduce(0) { count, action in
      if case .turn = action.operation { return count + 1 }
      return count
    }
  }
  public var isComplete: Bool { acknowledgedActions == actions.count }
  public init(plan: VerifiedPlan, revision: UInt64, acknowledgedActions: Int = 0) throws {
    guard (0...90).contains(acknowledgedActions) else { throw GuidePlanningError.invalidActionID }
    var state = plan.original
    var pose = CubeOrientation.identity
    var actions: [GuideAction] = []
    for (index, move) in plan.moves.enumerated() {
      let step = try GuidePlanner.actions(
        for: move, at: pose, state: state,
        sessionRevision: revision, moveIndex: index)
      guard let endpoint = step.last else { throw GuidePlanningError.invalidState }
      actions += step
      state = endpoint.after
      pose = endpoint.toPose
    }
    guard acknowledgedActions <= actions.count else { throw GuidePlanningError.invalidActionID }
    self.plan = plan
    self.revision = revision
    self.acknowledgedActions = acknowledgedActions
    self.actions = actions
  }
  public func acknowledging(_ id: ActionID) throws -> GuideProgress {
    guard pending?.id == id else { throw GuidePlanningError.invalidActionID }
    return try GuideProgress(
      plan: plan, revision: revision, acknowledgedActions: acknowledgedActions + 1)
  }
}
