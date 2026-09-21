import CubeCore
import CubeScan
@testable import CubeSession
import RealityKit
import Testing
@testable import cubeguide

extension PresentationTests {
  @MainActor
  struct CubeInstructionOverlayTests {
    @Test("A03/V10: front turns visibly highlight all nine layer bodies and retain cues before playback")
    func frontLayerCue() throws {
      let draft = try PracticeExample.draft()
      let state = try draft.canonicalFacelets()
      let scene = CubeSceneModel(draft: draft)
      for turns in QuarterTurns.allCases {
        let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: turns),
          at: .identity, state: state, sessionRevision: 1, moveIndex: 0).last)
        scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
        try checkHighlights(scene, wholeCube: false)
        scene.samplePreview(progress: 0.5)
        try checkHighlights(scene, wholeCube: false)
        // Guidance preparation cancels animation before enabling Play. The
        // instruction must remain visible while the physical cube is aligned.
        scene.cancelPreview()
        try checkHighlights(scene, wholeCube: false)
        scene.display(draft: draft, pose: .identity, showColorLabels: true)
        #expect(scene.root.findEntity(named: "instruction.direction") == nil)
        #expect(scene.bodies.values.allSatisfy {
          $0.findEntity(named: "instruction.highlight") == nil
        })
      }
    }

    @Test("A03/V10: every whole-cube regrip highlights all bodies without an occluding 3D direction cue")
    func wholeCubeCue() throws {
      let draft = try PracticeExample.draft()
      let state = try draft.canonicalFacelets()
      let scene = CubeSceneModel(draft: draft)
      let operations: [Regrip] = [.yawLeft, .yawRight, .topToward, .bottomToward,
        .rollClockwise, .rollCounterclockwise]
      for operation in operations {
        let action = GuideAction(id: try ActionID(sessionRevision: 1, moveIndex: 0, actionIndex: 0),
          operation: .regrip(operation), before: state, after: state,
          fromPose: .identity, toPose: CubeOrientation.identity.regripped(operation))
        scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
        try checkHighlights(scene, wholeCube: true)
        scene.samplePreview(progress: 0.5)
        try checkHighlights(scene, wholeCube: true)
        scene.cancelPreview()
        try checkHighlights(scene, wholeCube: true)
      }
    }

    @Test("A03/V10: every planned face and pose retains only selected highlights through finish and cancellation")
    func allPoseHighlightLifecycle() throws {
      let draft = try PracticeExample.draft()
      let state = try draft.canonicalFacelets()
      let scene = CubeSceneModel(draft: draft)
      let bodies = scene.bodies.mapValues { ObjectIdentifier($0) }
      for pose in CubeOrientation.all {
        for face in Face.allCases {
          for turns in QuarterTurns.allCases {
            let actions = try GuidePlanner.actions(for: Move(face: face, turns: turns),
              at: pose, state: state, sessionRevision: 1, moveIndex: 0)
            for action in actions {
              scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
              for progress in [0.0, 0.5, 1.0] {
                scene.samplePreview(progress: progress)
                for (point, body) in scene.bodies {
                  let selected: Bool
                  if case .turn(let move) = action.operation { selected = point.isOnLayer(move.face) }
                  else { selected = true }
                  #expect(body.children.filter { $0.name == "instruction.highlight" }.count == (selected ? 1 : 0))
                }
              }
              scene.cancelPreview()
              #expect(scene.root.children.count == 26)
              #expect(scene.root.findEntity(named: "instruction.direction") == nil)
            }
          }
        }
      }
      #expect(scene.bodies.mapValues { ObjectIdentifier($0) } == bodies)
      scene.display(draft: draft, pose: .identity, showColorLabels: true)
      #expect(scene.bodies.values.allSatisfy { $0.findEntity(named: "instruction.highlight") == nil })
    }

    private func checkHighlights(_ scene: CubeSceneModel, wholeCube: Bool) throws {
      var count = 0
      for (point, body) in scene.bodies {
        let highlight = body.findEntity(named: "instruction.highlight")
        if wholeCube || point.z == 1 {
          let visible = try #require(highlight)
          #expect(visible.isEnabled)
          let bounds = visible.visualBounds(relativeTo: body)
          #expect(bounds.extents.x > 0 && bounds.extents.y > 0 && bounds.extents.z > 0)
          count += 1
        } else {
          #expect(highlight == nil)
        }
      }
      #expect(count == (wholeCube ? 26 : 9))
    }

  }
}
