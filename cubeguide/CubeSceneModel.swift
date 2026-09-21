import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI
import UIKit

/// Scene entities are a presentation of immutable input; they never edit the draft.
@MainActor
final class CubeSceneModel {
  let root = Entity()
  private(set) var bodies: [CubePosition: ModelEntity] = [:]
  private(set) var stickers: [Int: ModelEntity] = [:]
  private static let bodyMesh = MeshResource.generateBox(size: 0.92, cornerRadius: 0.06)
  private static let stickerMesh = MeshResource.generateBox(
    size: SIMD3(0.82, 0.82, 0.025), cornerRadius: 0.012)
  private static var labelMeshes: [String: MeshResource] = [:]

  init(draft: ManualDraft, pose: CubeOrientation = .identity, showColorLabels: Bool = true) {
    root.name = "cube"
    // One lattice unit is one 2 cm cubie in this non-AR scene.
    root.scale = SIMD3(repeating: 0.02)
    for point in CubeGeometry.cubies {
      let body = ModelEntity(mesh: Self.bodyMesh,
        materials: [SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), roughness: 0.65, isMetallic: false)])
      body.name = "cubie.\(point.x).\(point.y).\(point.z)"
      bodies[point] = body
      root.addChild(body)
    }
    for placement in CubeGeometry.stickers {
      let sticker = ModelEntity(mesh: Self.stickerMesh, materials: [])
      sticker.name = "sticker.\(placement.index)"
      stickers[placement.index] = sticker
      bodies[placement.position]?.addChild(sticker)
    }
    display(draft: draft, pose: pose, showColorLabels: showColorLabels)
  }

  func display(draft: ManualDraft, pose: CubeOrientation, showColorLabels: Bool) {
    for (point, body) in bodies {
      body.transform = Transform(translation: vector(point.viewed(at: pose)))
    }
    for source in CubeGeometry.stickers {
      guard let sticker = stickers[source.index] else { continue }
      let placed = source.viewed(at: pose)
      let normal = vector(CubeGeometry.axis(for: placed.normal))
      let top = vector(CubeGeometry.axis(for: placed.top))
      let right = simd_cross(top, normal)
      sticker.transform = Transform(rotation: simd_quatf(simd_float3x3(columns: (right, top, normal))),
        translation: normal * 0.48)
      let color = draft.cells[source.index]
      let tint = color.map { UIColor($0.swatch) } ?? UIColor(white: 0.30, alpha: 1)
      sticker.model?.materials = [SimpleMaterial(color: tint, roughness: 0.6, isMetallic: false)]
      let label: String?
      if let color { label = showColorLabels ? String(color.title.prefix(1)) : nil }
      else { label = "?" }
      updateLabel(label, on: sticker, light: color == nil || color == .blue)
    }
  }

  private func updateLabel(_ text: String?, on sticker: ModelEntity, light: Bool) {
    for child in Array(sticker.children) { child.removeFromParent() }
    guard let text else { return }
    let mesh: MeshResource
    if let cached = Self.labelMeshes[text] { mesh = cached }
    else {
      mesh = .generateText(text, extrusionDepth: 0.002,
        font: .systemFont(ofSize: 1, weight: .bold))
      Self.labelMeshes[text] = mesh
    }
    let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: light ? .white : .black)])
    label.name = "label.\(text)"
    let scale = 0.44 / max(mesh.bounds.extents.x, mesh.bounds.extents.y, 0.001)
    label.scale = SIMD3(repeating: scale)
    label.position = -mesh.bounds.center * scale + SIMD3(0, 0, 0.018)
    sticker.addChild(label)
  }

  private func vector(_ point: CubePosition) -> SIMD3<Float> {
    SIMD3(Float(point.x), Float(point.y), Float(point.z))
  }
}
