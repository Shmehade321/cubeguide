import CubeCore
import CubeScan
@testable import CubeSession
import RealityKit
import Testing
@testable import cubeguide

extension PresentationTests {
@MainActor
struct CubeAnimationTests {
  @Test("V10: front demonstration moves one full layer about its center, leaving other cubies fixed")
  func layerSamples() throws {
    let draft = try PracticeExample.draft()
    let state = try draft.canonicalFacelets()
    let scene = CubeSceneModel(draft: draft)
    for turns in QuarterTurns.allCases {
      let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: turns),
        at: .identity, state: state, sessionRevision: 1, moveIndex: 0).last)
      scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
      let selected = scene.bodies.values.filter { $0.parent !== scene.root }
      try #require(selected.count == 9)
      let pivot = try #require(selected.first?.parent)
      #expect(selected.allSatisfy { $0.parent === pivot })
      #expect(pivot.children.count == 9)
      scene.samplePreview(progress: 0.5)
      // Independently specified halfway angles: clockwise -45, inverse +45, half -90.
      let angle: Float = turns == .half ? -.pi / 2 : turns == .clockwise ? -.pi / 4 : .pi / 4
      let rotation = simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))
      for (point, body) in scene.bodies {
        let before = vector(point)
        let expected = point.z == 1 ? rotation.act(before) : before
        #expect(simd_length(body.position(relativeTo: scene.root) - expected) < 0.00001)
      }
      // Absolute sampling must not accumulate repeated frame rotations.
      scene.samplePreview(progress: 0.5)
      let corner = try #require(scene.bodies.first { $0.key.x == 1 && $0.key.y == 1 && $0.key.z == 1 }?.value)
      #expect(simd_length(corner.position(relativeTo: scene.root) - rotation.act(SIMD3(1, 1, 1))) < 0.00001)
      scene.samplePreview(progress: 1)
      try assertResting(scene, state: action.after, pose: action.toPose, palette: draft.palette)
      scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
      scene.samplePreview(progress: 0.7)
      scene.cancelPreview()
      try assertResting(scene, state: action.before, pose: action.fromPose, palette: draft.palette)
    }
  }

  @Test("R11/V10: cancelling a finished expected-after preview restores before and ignores later samples")
  func cancelFinishedPreview() throws {
    let draft = try PracticeExample.draft()
    let state = try draft.canonicalFacelets()
    let scene = CubeSceneModel(draft: draft)
    let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: .clockwise),
      at: .identity, state: state, sessionRevision: 1, moveIndex: 0).last)
    scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
    scene.samplePreview(progress: 1)
    scene.cancelPreview()
    scene.samplePreview(progress: 1)
    try assertResting(scene, state: state, pose: .identity, palette: draft.palette)
  }

  @Test("V10: every planned move/pose snaps actual entities to canonical endpoints without retained pivots")
  func allEndpoints() throws {
    let draft = try PracticeExample.draft()
    let state = try draft.canonicalFacelets()
    let scene = CubeSceneModel(draft: draft)
    for pose in CubeOrientation.all {
      for face in Face.allCases {
        for turns in QuarterTurns.allCases {
          let actions = try GuidePlanner.actions(for: Move(face: face, turns: turns), at: pose,
            state: state, sessionRevision: 1, moveIndex: 0)
          for action in actions {
            scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
            if case .regrip = action.operation {
              try #require(scene.bodies.values.filter { $0.parent !== scene.root }.count == 26)
            }
            scene.samplePreview(progress: 0.37)
            scene.samplePreview(progress: 1)
            try assertResting(scene, state: action.after, pose: action.toPose, palette: draft.palette)
          }
        }
      }
    }
  }

  @Test("V10: all six regrips rotate every cubie with the specified viewer-axis sign in every pose")
  func allRegripSamples() throws {
    let draft = try PracticeExample.draft()
    let state = try draft.canonicalFacelets()
    let scene = CubeSceneModel(draft: draft)
    let cases: [(Regrip, SIMD3<Float>, Float)] = [
      (.yawLeft, SIMD3(0,1,0), -.pi / 4),
      (.yawRight, SIMD3(0,1,0), .pi / 4),
      (.topToward, SIMD3(1,0,0), .pi / 4),
      (.bottomToward, SIMD3(1,0,0), -.pi / 4),
      (.rollClockwise, SIMD3(0,0,1), -.pi / 4),
      (.rollCounterclockwise, SIMD3(0,0,1), .pi / 4),
    ]
    for pose in CubeOrientation.all {
      for (operation, axis, angle) in cases {
        // Test-only access to the value's internal initializer lets us qualify
        // roll operations even though shortest front-face plans rarely need them.
        let action = GuideAction(id: try ActionID(sessionRevision: 1, moveIndex: 0, actionIndex: 0),
          operation: .regrip(operation), before: state, after: state,
          fromPose: pose, toPose: pose.regripped(operation))
        scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
        scene.samplePreview(progress: 0.5)
        let rotation = simd_quatf(angle: angle, axis: axis)
        for (point, body) in scene.bodies {
          #expect(body.parent !== scene.root)
          let expected = rotation.act(vector(point.viewed(at: pose)))
          #expect(simd_length(body.position(relativeTo: scene.root) - expected) < 0.00001)
        }
        for placement in CubeGeometry.stickers {
          let sticker = try #require(scene.stickers[placement.index])
          let beforeNormal = vector(CubeGeometry.axis(for: pose.viewFace(for: placement.normal)))
          let actual = sticker.orientation(relativeTo: scene.root).act(SIMD3(0,0,1))
          #expect(simd_length(actual - rotation.act(beforeNormal)) < 0.00001)
        }
        scene.samplePreview(progress: 1)
        try assertResting(scene, state: state, pose: action.toPose, palette: draft.palette)
      }
    }
  }

  @Test("V10: one thousand sequential turns with regrips and interrupted replays retain exact resting geometry")
  func longSequence() throws {
    let draft = try PracticeExample.draft()
    var state = try draft.canonicalFacelets()
    var pose = CubeOrientation.identity
    let scene = CubeSceneModel(draft: draft)
    let identities = scene.bodies.mapValues { ObjectIdentifier($0) }
    for index in 0..<1000 {
      let face = Face.allCases[index % 6]
      let turns = QuarterTurns.allCases[(index / 6) % 3]
      let actions = try GuidePlanner.actions(for: Move(face: face, turns: turns), at: pose,
        state: state, sessionRevision: UInt64(index + 1), moveIndex: 0)
      for action in actions {
        scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
        scene.samplePreview(progress: 0.37)
        if index % 11 == 0 {
          scene.cancelPreview()
          try assertResting(scene, state: action.before, pose: action.fromPose, palette: draft.palette)
          scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
          scene.samplePreview(progress: 0.63)
        }
        scene.samplePreview(progress: 1)
        try assertResting(scene, state: action.after, pose: action.toPose, palette: draft.palette)
        state = action.after
        pose = action.toPose
      }
    }
    #expect(scene.bodies.mapValues { ObjectIdentifier($0) } == identities)
    #expect(scene.stickers.count == 54)
  }

  private func assertResting(_ scene: CubeSceneModel, state: Facelets, pose: CubeOrientation,
    palette: CenterPalette) throws {
    #expect(scene.root.children.count == 26)
    for (point, body) in scene.bodies {
      #expect(body.parent === scene.root)
      #expect(body.position == vector(point.viewed(at: pose)))
      #expect(simd_length(body.orientation.act(SIMD3(1, 0, 0)) - SIMD3(1, 0, 0)) < 0.000001)
    }
    for placement in CubeGeometry.stickers {
      let sticker = try #require(scene.stickers[placement.index])
      let color = palette.colors[Int(state.faces[placement.index].rawValue)]
      #expect(sticker.findEntity(named: "label.\(color.title.prefix(1))") != nil)
      let actual = sticker.orientation(relativeTo: scene.root).act(SIMD3(0, 0, 1))
      let expected = vector(CubeGeometry.axis(for: pose.viewFace(for: placement.normal)))
      #expect(simd_length(actual - expected) < 0.000001)
    }
  }
  private func vector(_ p: CubePosition) -> SIMD3<Float> { SIMD3(Float(p.x), Float(p.y), Float(p.z)) }
}
}
