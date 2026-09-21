import CubeCore
import CubeScan
import CubeSession
import SwiftUI

/// Two discrete states and a fixed direction cue. No ARView or animation clock.
struct StaticGuideView: View {
  let action: GuideAction
  let palette: CenterPalette
  let after: Bool
  let showColorLabels: Bool
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  var body: some View {
    let drawing = StaticCubeDrawing(state: after ? action.after : action.before,
      pose: after ? action.toPose : action.fromPose, palette: palette)
    let direction = GuideDirectionStroke(operation: action.operation)
    VStack(spacing: 8) {
      Text(after ? "Static expected after this action" : "Static before this action")
        .font(.subheadline)
      Canvas { context, size in
          for sticker in drawing.stickers {
            let points = sticker.corners.map { screen($0, size: size) }
            let shape = polygon(points)
            context.fill(shape, with: .color(sticker.color.swatch))
            let moving = direction.movingCubies == 26 ||
              CubeGeometry.stickers[sticker.index].position.isOnLayer(.front)
            context.stroke(shape, with: .color(.primary), lineWidth: moving ? 3 : 1)
            if showColorLabels {
              let center = CGPoint(x: points.map(\.x).reduce(0,+) / 4,
                y: points.map(\.y).reduce(0,+) / 4)
              context.draw(Text(String(sticker.color.title.prefix(1)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(sticker.color == .blue ? Color.white : Color.black), at: center)
            }
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(after ? "Static expected-after cube" : "Static before cube")
        .accessibilityIdentifier("guide.staticCube")
        .frame(height: verticalSizeClass == .compact ? 120 : 180)

      GuideDirectionDiagram(action: action, palette: palette, after: after)
    }
    .foregroundStyle(.primary)
  }

  private func screen(_ point: SIMD3<Float>, size: CGSize, inset: CGFloat = 0) -> CGPoint {
    let projected = StaticCubeDrawing.project(point)
    let scale = min((size.width - 2 * inset) / 6.5, (size.height - 2 * inset) / 5.8)
    return CGPoint(x: size.width / 2 + projected.x * scale,
      y: size.height / 2 + projected.y * scale)
  }

  private func polygon(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
  }
}
