import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI

struct CubePreviewScreen: View {
  let draft: ManualDraft
  let showColorLabels: Bool
  @State private var pose = CubeOrientation.identity
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Back to colors", systemImage: "chevron.left") { dismiss() }
          .accessibilityIdentifier("preview.done")
        Spacer()
        Text("3D preview").font(.headline).accessibilityAddTraits(.isHeader)
      }.padding()
      ScrollView {
        VStack(spacing: 16) {
          Text("\(54 - draft.missingCount) entered stickers · \(draft.missingCount) unknown")
          Group {
            if CubeRendererPolicy.requiresStaticRenderer() {
              StaticDraftCube(draft: draft, pose: pose, showColorLabels: showColorLabels)
            } else {
              CubeSceneView(draft: draft, pose: pose, showColorLabels: showColorLabels)
            }
          }
            .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("3D preview of entered colors")
            .accessibilityValue("\(draft.missingCount) unknown stickers, marked with question marks")
            .accessibilityIdentifier("preview.cube")
          Text("Front: \(color(at: .front)) · Top: \(color(at: .up)) · Right: \(color(at: .right))")
            .font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("preview.pose")
          Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
              turn("Rotate left", operation: .yawLeft, id: "preview.left")
              turn("Rotate right", operation: .yawRight, id: "preview.right")
            }
            GridRow {
              turn("Show top", operation: .topToward, id: "preview.top")
              turn("Show bottom", operation: .bottomToward, id: "preview.bottom")
            }
          }
          Button("Reset view") { pose = .identity }
            .buttonStyle(.bordered).disabled(pose == .identity).accessibilityIdentifier("preview.reset")
          Text("Rotate the preview to inspect other faces. Your entries stay the same. Question marks show stickers you haven't entered.")
            .font(.footnote).foregroundStyle(.secondary)
        }.padding()
      }
    }
    .toolbar(.hidden, for: .navigationBar, .bottomBar)
  }

  private func color(at face: Face) -> String {
    draft.palette.colors[Int(pose.canonicalFace(at: face).rawValue)].title
  }
  private func turn(_ title: String, operation: Regrip, id: String) -> some View {
    Button(title) { pose = pose.regripped(operation) }
      .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
      .accessibilityIdentifier(id)
  }
}

private struct StaticDraftCube: View {
  let draft: ManualDraft
  let pose: CubeOrientation
  let showColorLabels: Bool

  var body: some View {
    Canvas { context, size in draw(in: &context, size: size) }
  }

  /// Drawing lives outside the view builder so each statement is type-checked on its own.
  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let scale = min(size.width / 6.5, size.height / 5.8)
    for placement in CubeGeometry.stickers.prefix(27) {
      guard let source = sourceSticker(for: placement) else { continue }
      let normal: SIMD3<Float> = StaticCubeDrawing.vector(CubeGeometry.axis(for: placement.normal))
      let top: SIMD3<Float> = StaticCubeDrawing.vector(CubeGeometry.axis(for: placement.top))
      let right: SIMD3<Float> = simd_cross(top, normal) * 0.46
      let up: SIMD3<Float> = top * 0.46
      let center: SIMD3<Float> = StaticCubeDrawing.vector(placement.position) + normal * 0.5
      let corners: [SIMD3<Float>] = [
        center - right + up, center + right + up, center + right - up, center - right - up,
      ]
      let points: [CGPoint] = corners.map { corner in
        let projected = StaticCubeDrawing.project(corner)
        return CGPoint(
          x: size.width / 2 + projected.x * scale, y: size.height / 2 + projected.y * scale)
      }
      var path = Path()
      path.addLines(points)
      path.closeSubpath()
      let color = draft.cells[source.index]
      let fill: Color = color?.swatch ?? Color.secondary.opacity(0.35)
      context.fill(path, with: .color(fill))
      context.stroke(path, with: .color(.primary), lineWidth: 1)
      if showColorLabels || color == nil {
        let x: CGFloat = points.map(\.x).reduce(0, +) / 4
        let y: CGFloat = points.map(\.y).reduce(0, +) / 4
        let label = color.map { String($0.title.prefix(1)) } ?? "?"
        let ink: Color = color == .blue || color == nil ? .white : .black
        let text: Text = Text(label).font(.caption.bold()).foregroundStyle(ink)
        context.draw(text, at: CGPoint(x: x, y: y))
      }
    }
  }

  private func sourceSticker(for placement: CubeStickerPlacement) -> CubeStickerPlacement? {
    CubeGeometry.stickers.first { sticker in
      let viewed = sticker.viewed(at: pose)
      return viewed.position == placement.position && viewed.normal == placement.normal
        && viewed.top == placement.top
    }
  }
}

struct CubeSceneView: UIViewRepresentable {
  let draft: ManualDraft
  let pose: CubeOrientation
  let showColorLabels: Bool
  @Environment(\.colorScheme) private var colorScheme

  final class Coordinator {
    let model: CubeSceneModel
    init(model: CubeSceneModel) { self.model = model }
  }
  func makeCoordinator() -> Coordinator {
    Coordinator(model: CubeSceneModel(draft: draft, pose: pose, showColorLabels: showColorLabels))
  }
  func makeUIView(context: Context) -> ARView {
    Self.makeView(model: context.coordinator.model)
  }
  static func makeView(model: CubeSceneModel) -> ARView {
    let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    view.isUserInteractionEnabled = false
    view.renderOptions = [.disableCameraGrain, .disableDepthOfField, .disableMotionBlur]
    let anchor = AnchorEntity(world: .zero)
    anchor.addChild(model.root)
    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = 38
    camera.look(at: .zero, from: SIMD3(0.11, 0.085, 0.14), relativeTo: nil)
    anchor.addChild(camera)
    let key = DirectionalLight()
    key.light.intensity = 2500
    key.look(at: .zero, from: SIMD3(-0.1, 0.2, 0.15), relativeTo: nil)
    anchor.addChild(key)
    let fill = DirectionalLight()
    fill.light.intensity = 1000
    fill.look(at: .zero, from: SIMD3(0.2, 0.06, 0.05), relativeTo: nil)
    anchor.addChild(fill)
    view.scene.addAnchor(anchor)
    return view
  }
  func updateUIView(_ view: ARView, context: Context) {
    context.coordinator.model.display(draft: draft, pose: pose, showColorLabels: showColorLabels)
    view.environment.background = .color(colorScheme == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.97, alpha: 1))
  }
  static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
    coordinator.model.root.removeFromParent()
    view.scene.anchors.removeAll()
    view.isHidden = true
  }
}
