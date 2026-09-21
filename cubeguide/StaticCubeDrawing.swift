import CoreGraphics
import CubeCore
import CubeScan
import CubeSession
import simd

struct StaticCubeSticker {
  let index: Int
  let color: CubeColor
  let corners: [SIMD3<Float>]
}

struct StaticCubeDrawing {
  let stickers: [StaticCubeSticker]
  init(state: Facelets, pose: CubeOrientation, palette: CenterPalette) {
    let viewed = pose.viewing(state)
    stickers = CubeGeometry.stickers.prefix(27).map { placement in
      let normal = Self.vector(CubeGeometry.axis(for: placement.normal))
      let top = Self.vector(CubeGeometry.axis(for: placement.top))
      let right = simd_cross(top, normal)
      let center = Self.vector(placement.position) + normal * 0.5
      let corners = [center - right * 0.46 + top * 0.46,
        center + right * 0.46 + top * 0.46,
        center + right * 0.46 - top * 0.46,
        center - right * 0.46 - top * 0.46]
      return StaticCubeSticker(index: placement.index,
        color: palette.colors[Int(viewed[placement.index].rawValue)], corners: corners)
    }
  }

  static func project(_ point: SIMD3<Float>) -> CGPoint {
    CGPoint(x: CGFloat(0.8 * (point.x - point.z)),
      y: CGFloat(-point.y + 0.4 * (point.x + point.z)))
  }

  static func vector(_ point: CubePosition) -> SIMD3<Float> {
    SIMD3(Float(point.x), Float(point.y), Float(point.z))
  }
}

struct GuideDirectionStroke {
  let points: [SIMD3<Float>]
  let movingCubies: Int
  init(operation: GuideOperation) {
    let rotation: CubeRotation
    let start: SIMD3<Float>
    let offset: SIMD3<Float>
    switch operation {
    case .turn(let move):
      rotation = CubeRotation(axis: .front, turns: move.turns)
      start = SIMD3(0,2,0)
      offset = SIMD3(0,0,1.8)
      movingCubies = 9
    case .regrip(let regrip):
      rotation = CubeRotation(regrip: regrip)
      switch regrip {
      case .yawLeft, .yawRight: start = SIMD3(0,0,2)
      case .bottomToward: start = SIMD3(0,-2,0)
      default: start = SIMD3(0,2,0)
      }
      offset = .zero
      movingCubies = 26
    }
    let axis = StaticCubeDrawing.vector(CubeGeometry.axis(for: rotation.axis))
    points = (0...32).map { step in
      let angle = Float(rotation.signedQuarterTurns) * .pi / 2 * Float(step) / 32
      return simd_quatf(angle: angle, axis: axis).act(start) + offset
    }
  }
}
