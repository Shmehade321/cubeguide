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
  private let pivot = Entity()
  private var highlights: [CubePosition: Entity] = [:]
  private var previewFinished = false
  private var displayedColors: [CubeColor?] = []
  private var preview: (action: GuideAction, palette: CenterPalette, labels: Bool, rotation: CubeRotation)?
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
    display(colors: draft.cells, pose: pose, showColorLabels: showColorLabels)
  }

  private func display(colors: [CubeColor?], pose: CubeOrientation, showColorLabels: Bool) {
    for highlight in highlights.values { highlight.removeFromParent() }
    displayedColors = colors
    preview = nil
    previewFinished = false
    for (point, body) in bodies {
      root.addChild(body)
      body.transform = Transform(translation: vector(point.viewed(at: pose)))
    }
    pivot.removeFromParent()
    pivot.transform = Transform()
    for source in CubeGeometry.stickers {
      guard let sticker = stickers[source.index] else { continue }
      let placed = source.viewed(at: pose)
      let normal = vector(CubeGeometry.axis(for: placed.normal))
      let top = vector(CubeGeometry.axis(for: placed.top))
      let right = simd_cross(top, normal)
      sticker.transform = Transform(rotation: simd_quatf(simd_float3x3(columns: (right, top, normal))),
        translation: normal * 0.48)
      let color = colors[source.index]
      let tint = color.map { UIColor($0.swatch) } ?? UIColor(white: 0.30, alpha: 1)
      sticker.model?.materials = [SimpleMaterial(color: tint, roughness: 0.6, isMetallic: false)]
    }
    setColorLabels(showColorLabels)
  }

  /// Refresh only glyphs, preserving an active pivot and every body/sticker transform.
  func setColorLabels(_ enabled: Bool) {
    if var current = preview {
      current.labels = enabled
      preview = current
    }
    for (index, sticker) in stickers {
      let color = displayedColors[index]
      let label: String?
      if let color { label = enabled ? String(color.title.prefix(1)) : nil }
      else { label = "?" }
      updateLabel(label, on: sticker, light: color == nil || color == .blue)
    }
  }

  func beginPreview(_ action: GuideAction, palette: CenterPalette, showColorLabels: Bool) {
    display(state: action.before, palette: palette, pose: action.fromPose, labels: showColorLabels)
    let rotation: CubeRotation
    switch action.operation {
    case .turn(let move):
      rotation = CubeRotation(axis: action.fromPose.viewFace(for: move.face), turns: move.turns)
    case .regrip(let operation): rotation = CubeRotation(regrip: operation)
    }
    root.addChild(pivot)
    for (point, body) in bodies {
      let selected: Bool
      if case .turn(let move) = action.operation { selected = point.isOnLayer(move.face) }
      else { selected = true }
      // The pivot is identity and shares the root's coordinates at preparation.
      if selected { pivot.addChild(body) }
    }
    preview = (action, palette, showColorLabels, rotation)
    showInstruction(action)
  }

  func samplePreview(progress: Double) {
    guard let current = preview, !previewFinished, progress.isFinite else { return }
    if progress >= 1 {
      display(state: current.action.after, palette: current.palette,
        pose: current.action.toPose, labels: current.labels)
      // Retain the immutable before-state until acknowledgement/replacement or cancellation.
      preview = current
      previewFinished = true
      showInstruction(current.action)
    } else {
      let angle = Float(max(0, progress)) * Float(current.rotation.signedQuarterTurns) * .pi / 2
      pivot.orientation = simd_quatf(angle: angle, axis: vector(CubeGeometry.axis(for: current.rotation.axis)))
    }
  }

  func cancelPreview() {
    guard let current = preview else { return }
    display(state: current.action.before, palette: current.palette,
      pose: current.action.fromPose, labels: current.labels)
    showInstruction(current.action)
  }

  private func showInstruction(_ action: GuideAction) {
    for (point, body) in bodies {
      let selected: Bool
      if case .turn(let move) = action.operation { selected = point.isOnLayer(move.face) }
      else { selected = true }
      guard selected else { continue }
      let highlight = highlights[point] ?? CubeInstructionOverlay.highlight()
      highlights[point] = highlight
      body.addChild(highlight)
    }

  }

  private func display(state: Facelets, palette: CenterPalette, pose: CubeOrientation, labels: Bool) {
    display(colors: state.faces.map { palette.colors[Int($0.rawValue)] },
      pose: pose, showColorLabels: labels)
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
