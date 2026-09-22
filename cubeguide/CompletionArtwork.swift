import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI

/// Displays the recorded result; never advances or confirms the physical cube.
struct CompletionArtwork: View {
  let state: Facelets
  let palette: CenterPalette
  let pose: CubeOrientation
  let showColorLabels: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var revealed = false

  var body: some View {
    VStack(spacing: 8) {
      if reduceMotion || CubeRendererPolicy.requiresStaticRenderer() {
        StaticCompletionCube(state: state, palette: palette, pose: pose, showColorLabels: showColorLabels)
      } else {
        CompletionSceneView(state: state, palette: palette, pose: pose, labels: showColorLabels)
          .accessibilityLabel("Expected solved cube")
          .accessibilityIdentifier("completion.renderedCube")
      }
      Image(systemName: "checkmark.circle")
        .font(.title).accessibilityHidden(true)
    }
    .frame(height: 210)
    .opacity(reduceMotion || CubeRendererPolicy.requiresStaticRenderer() || revealed ? 1 : 0)
    .onAppear {
      if reduceMotion || CubeRendererPolicy.requiresStaticRenderer() { revealed = true }
      else { withAnimation(.easeOut(duration: 0.2)) { revealed = true } }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("completion.artwork")
    .accessibilityValue(visibleCenters)
  }

  private var visibleCenters: String {
    let viewed = pose.viewing(state)
    let colors = [22, 4, 13].map { palette.colors[Int(viewed[$0].rawValue)].title }
    return "Front \(colors[0]), top \(colors[1]), right \(colors[2])"
  }
}

struct StaticCompletionCube: View {
  let state: Facelets
  let palette: CenterPalette
  let pose: CubeOrientation
  let showColorLabels: Bool

  var body: some View {
    Canvas { context, size in
      let drawing = StaticCubeDrawing(state: state, pose: pose, palette: palette)
      for sticker in drawing.stickers {
        let points = sticker.corners.map { corner in
          let point = StaticCubeDrawing.project(corner)
          let scale = min(size.width / 6.5, size.height / 5.8)
          return CGPoint(x: size.width / 2 + point.x * scale,
            y: size.height / 2 + point.y * scale)
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        context.fill(path, with: .color(sticker.color.swatch))
        context.stroke(path, with: .color(.primary), lineWidth: 1)
        if showColorLabels {
          let center = CGPoint(x: points.map(\.x).reduce(0, +) / 4,
            y: points.map(\.y).reduce(0, +) / 4)
          context.draw(Text(String(sticker.color.title.prefix(1)))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(sticker.color == .blue ? Color.white : Color.black), at: center)
        }
      }
    }
    .accessibilityLabel("Expected solved cube")
    .accessibilityIdentifier("completion.staticCube")
  }
}

private struct CompletionSceneView: UIViewRepresentable {
  let state: Facelets
  let palette: CenterPalette
  let pose: CubeOrientation
  let labels: Bool
  @Environment(\.colorScheme) private var colorScheme
  typealias Coordinator = CubeSceneView.Coordinator

  func makeCoordinator() -> Coordinator {
    let model = CubeSceneModel(draft: ManualDraft(palette: palette))
    model.display(state: state, palette: palette, pose: pose, labels: labels)
    return Coordinator(model: model)
  }

  func makeUIView(context: Context) -> ARView {
    CubeSceneView.makeView(model: context.coordinator.model)
  }

  func updateUIView(_ view: ARView, context: Context) {
    context.coordinator.model.display(state: state, palette: palette, pose: pose, labels: labels)
    view.environment.background = .color(colorScheme == .dark
      ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.97, alpha: 1))
  }

  static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
    CubeSceneView.dismantleUIView(view, coordinator: coordinator)
  }
}
