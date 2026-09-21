import CubeCore
import Foundation
import CubeScan
import CubeSession
import Testing
import simd
@testable import cubeguide

extension PresentationTests {
  struct StaticCubeDrawingTests {
    @Test("R07/R12: static cube preserves visible row/column colors and projects all three faces")
    @MainActor func visibleFacelets() throws {
      let state = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
      let palette = try PracticeExample.draft().palette
      let drawing = StaticCubeDrawing(state: state, pose: .identity, palette: palette)
      try #require(drawing.stickers.count == 27)
      #expect(drawing.stickers.filter { $0.index < 9 }.map(\.color) ==
        [.white,.white,.green,.white,.white,.green,.white,.white,.green])
      #expect(drawing.stickers.filter { (18..<27).contains($0.index) }.map(\.color) ==
        [.green,.green,.yellow,.green,.green,.yellow,.green,.green,.yellow])
      #expect(drawing.stickers.filter { (9..<18).contains($0.index) }.map(\.color) == Array(repeating: .red, count: 9))
      let yawed = StaticCubeDrawing(state: state, pose: .identity.regripped(.yawLeft), palette: palette)
      #expect(yawed.stickers.filter { (18..<27).contains($0.index) }.map(\.color) == Array(repeating: .red, count: 9))
      #expect(yawed.stickers.filter { (9..<18).contains($0.index) }.map(\.color) ==
        [.white,.blue,.blue,.white,.blue,.blue,.white,.blue,.blue])
      let frontCenter = try #require(drawing.stickers.first { $0.index == 22 })
      try #require(frontCenter.corners.count == 4)
      #expect(frontCenter.corners.allSatisfy { abs($0.z - 1.5) < 0.00001 })
      #expect(frontCenter.corners[0].x < 0 && frontCenter.corners[0].y > 0)
      #expect(frontCenter.corners[1].x > 0 && frontCenter.corners[1].y > 0)
      #expect(frontCenter.corners[2].x > 0 && frontCenter.corners[2].y < 0)
      let front = StaticCubeDrawing.project(SIMD3(0,0,1))
      let right = StaticCubeDrawing.project(SIMD3(1,0,0))
      let top = StaticCubeDrawing.project(SIMD3(0,1,0))
      #expect(front.x < 0 && front.y > 0 && right.x > 0 && right.y > 0)
      #expect(top.x == 0 && top.y < 0)
      for pose in CubeOrientation.all {
        let view = StaticCubeDrawing(state: state, pose: pose, palette: palette)
        #expect(Set(view.stickers.map(\.index)) == Set(0..<27))
        #expect(view.stickers.allSatisfy { $0.corners.count == 4 })
      }
    }

    @Test("R08/R12: static arrows distinguish front-layer turns from every whole-cube regrip direction")
    @MainActor func arrowDirections() throws {
      // Literal viewer-space endpoints independently encode the documented
      // physical direction. Reversing a sign or highlighting the whole cube
      // for a face turn must fail these assertions.
      let cases: [(GuideOperation, SIMD3<Float>, SIMD3<Float>, Int)] = [
        (.turn(Move(face: .front, turns: .clockwise)), SIMD3(0,2,1.8), SIMD3(2,0,1.8), 9),
        (.turn(Move(face: .front, turns: .counterclockwise)), SIMD3(0,2,1.8), SIMD3(-2,0,1.8), 9),
        (.turn(Move(face: .front, turns: .half)), SIMD3(0,2,1.8), SIMD3(0,-2,1.8), 9),
        (.regrip(.yawLeft), SIMD3(0,0,2), SIMD3(-2,0,0), 26),
        (.regrip(.yawRight), SIMD3(0,0,2), SIMD3(2,0,0), 26),
        (.regrip(.topToward), SIMD3(0,2,0), SIMD3(0,0,2), 26),
        (.regrip(.bottomToward), SIMD3(0,-2,0), SIMD3(0,0,2), 26),
        (.regrip(.rollClockwise), SIMD3(0,2,0), SIMD3(2,0,0), 26),
        (.regrip(.rollCounterclockwise), SIMD3(0,2,0), SIMD3(-2,0,0), 26),
      ]
      for (operation, start, end, count) in cases {
        let stroke = GuideDirectionStroke(operation: operation)
        try #require(stroke.points.count > 2)
        #expect(simd_length(stroke.points[0] - start) < 0.00001)
        #expect(simd_length(stroke.points[stroke.points.count - 1] - end) < 0.00001)
        #expect(stroke.movingCubies == count)
        #expect(stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
      }
    }
  }
}
