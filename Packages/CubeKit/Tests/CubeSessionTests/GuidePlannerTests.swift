import CubeCore
import Foundation
import Testing

@testable import CubeSession

@Test("V09: stable regrips put every canonical face at front before its turn")
func literalGuidePaths() throws {
  let paths: [(Face, [Regrip])] = [
    (.front, []), (.right, [.yawLeft]),
    (.left, [.yawRight]), (.up, [.topToward]), (.down, [.bottomToward]),
    (.back, [.yawLeft, .yawLeft]),
  ]
  for (face, expected) in paths {
    let move = Move(face: face, turns: .clockwise)
    let actions = try GuidePlanner.actions(
      for: move, at: .identity, state: .solved,
      sessionRevision: 9, moveIndex: 0)
    let actual = actions.compactMap { action -> Regrip? in
      if case .regrip(let operation) = action.operation { return operation }
      return nil
    }
    #expect(actual == expected)
    #expect(actions.count == expected.count + 1)
    #expect(actions.last?.operation == .turn(move))
    #expect(actions.last?.demonstratedMove == Move(face: .front, turns: .clockwise))
  }
}

@Test(
  "V09: 24 poses times 18 moves preserve puzzle state during regrips and reconstruct each canonical turn"
)
func everyGuidePoseAndMove() throws {
  let baseline = Facelets.solved.applying(try Move.parse("R U R' U' F2"))
  var checked = 0
  for initialPose in CubeOrientation.all {
    for face in Face.allCases {
      for amount in QuarterTurns.allCases {
        let move = Move(face: face, turns: amount)
        let actions = try GuidePlanner.actions(
          for: move, at: initialPose, state: baseline,
          sessionRevision: 42, moveIndex: 7)
        try #require(!actions.isEmpty)
        #expect(actions.count <= 3)
        #expect(Set(actions.map(\.id)).count == actions.count)
        var pose = initialPose
        for (index, action) in actions.enumerated() {
          #expect(action.id.sessionRevision == 42)
          #expect(action.id.moveIndex == 7)
          #expect(action.id.actionIndex == index)
          #expect(action.fromPose == pose)
          #expect(action.before == baseline)
          switch action.operation {
          case .regrip(let operation):
            #expect(action.after == baseline)
            #expect(action.toPose == pose.regripped(operation))
            #expect(action.demonstratedMove == nil)
          case .turn(let canonical):
            #expect(index == actions.count - 1)
            #expect(canonical == move)
            #expect(action.fromPose == action.toPose)
            #expect(pose.viewFace(for: face) == .front)
            #expect(action.after == baseline.applying([move]))
            let beforeInView = try Facelets(pose.viewing(baseline))
            let expectedInView = try Facelets(pose.viewing(baseline.applying([move])))
            #expect(
              beforeInView.applying([try #require(action.demonstratedMove)]) == expectedInView)
          }
          pose = action.toPose
        }
        if initialPose.viewFace(for: face) == .front { #expect(actions.count == 1) }
        if actions.count == 3 {
          #expect(
            !Regrip.allCases.contains { initialPose.regripped($0).viewFace(for: face) == .front })
        }
        checked += 1
      }
    }
  }
  #expect(checked == 432)
}

@Test("V11: action identity rejects out-of-range move/action indices, including decoded values")
func boundedActionIdentity() throws {
  for (move, action) in [(-1, 0), (30, 0), (0, -1), (0, 3), (Int.max, 0)] {
    #expect(throws: GuidePlanningError.self) {
      try ActionID(sessionRevision: 1, moveIndex: move, actionIndex: action)
    }
    let data = Data("{\"sessionRevision\":1,\"moveIndex\":\(move),\"actionIndex\":\(action)}".utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ActionID.self, from: data) }
  }
  for move in [0, 29] {
    for action in 0...2 {
      let id = try ActionID(sessionRevision: 10, moveIndex: move, actionIndex: action)
      #expect(try JSONDecoder().decode(ActionID.self, from: JSONEncoder().encode(id)) == id)
    }
  }
}
