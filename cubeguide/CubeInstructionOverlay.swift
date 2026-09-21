import RealityKit
import UIKit

/// Presentation geometry only. Highlight rails follow the selected cubies.
@MainActor
enum CubeInstructionOverlay {
  private static let beam = MeshResource.generateBox(size: 1)

  static func highlight() -> Entity {
    let result = Entity()
    result.name = "instruction.highlight"
    for axis in 0..<3 {
      for a: Float in [-0.49, 0.49] {
        for b: Float in [-0.49, 0.49] {
          var start = SIMD3<Float>(repeating: 0)
          start[axis] = -0.49
          start[(axis + 1) % 3] = a
          start[(axis + 2) % 3] = b
          var end = start
          end[axis] = 0.49
          addStroke(from: start, to: end, width: 0.025, to: result)
        }
      }
    }
    return result
  }

  private static func addStroke(from start: SIMD3<Float>, to end: SIMD3<Float>,
    width: Float, to parent: Entity) {
    let delta = end - start
    let length = simd_length(delta)
    guard length > 0 else { return }
    let entity = ModelEntity(mesh: beam, materials: [UnlitMaterial(color: .systemTeal)])
    entity.transform = Transform(scale: SIMD3(width, length, width),
      rotation: simd_quatf(from: SIMD3(0, 1, 0), to: delta / length),
      translation: (start + end) / 2)
    parent.addChild(entity)
  }
}
