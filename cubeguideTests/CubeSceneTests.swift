import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI
import Testing
import UIKit
@testable import cubeguide

@MainActor
struct CubeSceneTests {
  @Test("R01/R18: preview uses a virtual camera with automatic AR disabled and detaches on teardown")
  func virtualCameraLifecycle() throws {
    let scene = CubeSceneModel(draft: try PracticeExample.draft())
    let view = CubeSceneView.makeView(model: scene)
    #expect(view.cameraMode == .nonAR)
    #expect(!view.automaticallyConfigureSession)
    try #require(view.scene.anchors.count == 1)
    let anchor = try #require(view.scene.anchors.first as? AnchorEntity)
    #expect(anchor.children.filter { $0 is PerspectiveCamera }.count == 1)
    #expect(anchor.children.filter { $0 is DirectionalLight }.count == 2)
    #expect(scene.root.parent === anchor)
    CubeSceneView.dismantleUIView(view, coordinator: CubeSceneView.Coordinator(model: scene))
    #expect(view.scene.anchors.isEmpty && scene.root.parent == nil && view.isHidden)
  }

  @Test("V10/A02: actual scene entities have all cubies/stickers and exact posed placement")
  func entityPlacement() throws {
    let draft = ManualDraft(palette: try CenterPalette([.green, .white, .orange, .blue, .yellow, .red]))
    let scene = CubeSceneModel(draft: draft)
    try #require(scene.bodies.count == 26 && scene.stickers.count == 54)
    #expect(scene.root.children.count == 26)
    for pose in CubeOrientation.all {
      scene.display(draft: draft, pose: pose, showColorLabels: true)
      for position in CubeGeometry.cubies {
        let body = try #require(scene.bodies[position])
        #expect(body.parent === scene.root)
        #expect(body.position == vector(position.viewed(at: pose)))
        #expect(body.model != nil)
      }
      for source in CubeGeometry.stickers {
        let sticker = try #require(scene.stickers[source.index])
        let placed = source.viewed(at: pose)
        let normal = vector(CubeGeometry.axis(for: placed.normal))
        let top = vector(CubeGeometry.axis(for: placed.top))
        #expect(sticker.parent === scene.bodies[source.position])
        #expect(simd_length(sticker.orientation.act(SIMD3(0, 0, 1)) - normal) < 0.000001)
        #expect(simd_length(sticker.orientation.act(SIMD3(0, 1, 0)) - top) < 0.000001)
        #expect(simd_length(sticker.position - normal * 0.48) < 0.000001)
      }
    }
    #expect(draft.missingCount == 48 && draft.revision == 0)
  }

  @Test("R03/V10: material colors use the actual incomplete draft without filling unknown stickers")
  func inputColors() throws {
    let initial = ManualDraft(palette: try CenterPalette([.blue, .orange, .white, .red, .green, .yellow]))
    let draft = try initial.setting(face: .front, row: 0, column: 2, color: .red)
    let scene = CubeSceneModel(draft: draft)
    try #require(scene.stickers.count == 54)
    for (index, color) in draft.cells.enumerated() {
      let sticker = try #require(scene.stickers[index])
      let material = try #require(sticker.model?.materials.first as? SimpleMaterial)
      let actual = try rgba(material.color.tint)
      if let color {
        let expected = try rgba(UIColor(color.swatch))
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.00001 })
        #expect(sticker.findEntity(named: "label.\(color.title.prefix(1))") != nil)
      } else {
        #expect(sticker.findEntity(named: "label.?") != nil)
        let palette = try CubeColor.allCases.map { try rgba(UIColor($0.swatch)) }
        #expect(palette.allSatisfy { expected in
          zip(actual, expected).contains { abs($0 - $1) > 0.01 }
        })
      }
    }
    #expect(draft.missingCount == 47 && initial.missingCount == 48)
  }

  @Test("R12/V10: updates retain scene identity and clear stale labels while unknown markers remain")
  func updatesAndLabels() throws {
    let draft = try PracticeExample.draft()
    let scene = CubeSceneModel(draft: draft)
    try #require(scene.stickers.count == 54)
    let original = try #require(scene.stickers[0])
    #expect(scene.stickers.values.allSatisfy { $0.children.count == 1 })
    scene.display(draft: draft, pose: .identity, showColorLabels: false)
    #expect(scene.stickers.values.allSatisfy { $0.children.isEmpty })
    let edited = try draft.setting(face: .up, row: 0, column: 0, color: nil)
    scene.display(draft: edited, pose: .identity, showColorLabels: false)
    #expect(scene.stickers[0] === original)
    #expect(original.findEntity(named: "label.?") != nil)
    #expect(scene.stickers.values.filter { !$0.children.isEmpty }.count == 1)
    scene.display(draft: draft, pose: .identity, showColorLabels: true)
    #expect(original.findEntity(named: "label.?") == nil)
    #expect(scene.bodies.count == 26 && scene.stickers.count == 54 && scene.root.children.count == 26)
    #expect(scene.stickers.values.allSatisfy { $0.children.count == 1 })
  }

  private func vector(_ point: CubePosition) -> SIMD3<Float> {
    SIMD3(Float(point.x), Float(point.y), Float(point.z))
  }

  private func rgba(_ color: UIColor) throws -> [CGFloat] {
    // RealityKit may return a linear-space UIColor. Compare physical colors in
    // one explicit space, not object identity or unmatched gamma-encoded values.
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let converted = try #require(color.cgColor.converted(to: space, intent: .defaultIntent, options: nil))
    let values = try #require(converted.components)
    try #require(values.count == 4)
    return values
  }
}
