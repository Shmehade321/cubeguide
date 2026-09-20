import CubeCore
import Testing

@testable import CubeSession

func twoMovePlan() throws -> VerifiedPlan {
  let moves = try Move.parse("R' U'")
  let original = Facelets.solved.applying(try Move.parse("U R"))
  let cube = try CubeValidation.validate(original).get()
  return try Replay.verify(moves, for: cube, resourceVersion: "fixture").get()
}

@Test("V09: a complete guide retains per-move IDs across regrips and only turns advance move count")
func stableGuideProgress() throws {
  let plan = try twoMovePlan()
  var progress = try GuideProgress(plan: plan, revision: 5)
  #expect(progress.actions.count <= 6)
  #expect(progress.acknowledgedActions == 0)
  #expect(!progress.isComplete)
  let first = try #require(progress.pending)
  #expect(first.id.moveIndex == 0 && first.id.actionIndex == 0)
  #expect(first.operation == .regrip(.yawLeft))
  progress = try progress.acknowledging(first.id)
  #expect(progress.acknowledgedActions == 1)
  #expect(progress.moveIndex == 0)
  #expect(progress.pose == CubeOrientation.identity.regripped(.yawLeft))
  #expect(progress.state == plan.original)
  let turn = try #require(progress.pending)
  #expect(turn.id.moveIndex == 0 && turn.id.actionIndex == 1)
  #expect(turn.operation == .turn(Move(face: .right, turns: .counterclockwise)))
  progress = try progress.acknowledging(turn.id)
  #expect(progress.moveIndex == 1)
  #expect(progress.state == plan.original.applying([plan.moves[0]]))
  let remaining = progress.actions.count - progress.acknowledgedActions
  for _ in 0..<remaining {
    progress = try progress.acknowledging(try #require(progress.pending).id)
  }
  #expect(progress.isComplete)
  #expect(progress.pending == nil)
  #expect(progress.state == .solved)
  #expect(progress.moveIndex == 2)
}

@Test(
  "V11: restored action offsets reproduce exact state/pose and invalid or duplicate acknowledgements fail"
)
func boundedGuideProgress() throws {
  let plan = try twoMovePlan()
  let initial = try GuideProgress(plan: plan, revision: 5)
  let first = try #require(initial.pending)
  let advanced = try initial.acknowledging(first.id)
  #expect(throws: GuidePlanningError.self) { try advanced.acknowledging(first.id) }
  let wrong = try ActionID(sessionRevision: 6, moveIndex: 0, actionIndex: 0)
  #expect(throws: GuidePlanningError.self) { try initial.acknowledging(wrong) }
  for count in [-1, 91, Int.max] {
    #expect(throws: GuidePlanningError.self) {
      try GuideProgress(plan: plan, revision: 5, acknowledgedActions: count)
    }
  }
  var expected = initial
  for count in 0...initial.actions.count {
    let restored = try GuideProgress(plan: plan, revision: 5, acknowledgedActions: count)
    #expect(restored == expected)
    if let pending = expected.pending { expected = try expected.acknowledging(pending.id) }
  }
  let solved = try CubeValidation.validate(.solved).get()
  let empty = try Replay.verify([], for: solved, resourceVersion: "fixture").get()
  let finished = try GuideProgress(plan: empty, revision: 9)
  #expect(finished.isComplete)
  #expect(finished.pending == nil)
  #expect(finished.state == .solved)
}

@Test("V11: progress constructor bounds and solved empty plans")
func guideProgressConstruction() throws {
  let plan = try twoMovePlan()
  for count in [-1, 91, Int.max] {
    #expect(throws: GuidePlanningError.self) {
      try GuideProgress(plan: plan, revision: 5, acknowledgedActions: count)
    }
  }
  let cube = try CubeValidation.validate(.solved).get()
  let planEmpty = try Replay.verify([], for: cube, resourceVersion: "fixture").get()
  #expect(try GuideProgress(plan: planEmpty, revision: 1).isComplete)
}
