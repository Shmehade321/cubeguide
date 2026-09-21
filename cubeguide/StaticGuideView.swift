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

      HStack(spacing: 12) {
        Canvas { context, size in
          // A separate neutral schematic keeps every comparison sticker readable.
          for sticker in drawing.stickers {
            let shape = polygon(sticker.corners.map { screen($0, size: size, inset: 8) })
            context.stroke(shape, with: .color(.secondary), lineWidth: 0.7)
          }
          let points = direction.points.map { screen($0, size: size, inset: 8) }
          var path = Path()
          if let first = points.first { path.move(to: first) }
          for point in points.dropFirst() { path.addLine(to: point) }
          context.stroke(path, with: .color(Color(uiColor: .systemBackground)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
          context.stroke(path, with: .color(.primary),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          if points.count >= 2 {
            let end = points[points.count - 1], previous = points[points.count - 2]
            let dx = end.x - previous.x, dy = end.y - previous.y
            let length = max(0.001, hypot(dx, dy))
            let x = dx / length, y = dy / length
            let head = polygon([end,
              CGPoint(x: end.x - 8*x + 4*y, y: end.y - 8*y - 4*x),
              CGPoint(x: end.x - 8*x - 4*y, y: end.y - 8*y + 4*x)])
            context.stroke(head, with: .color(Color(uiColor: .systemBackground)), lineWidth: 2)
            context.fill(head, with: .color(.primary))
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction.movingCubies == 9 ? "Front-layer direction arrow" : "Whole-cube direction arrow")
        .accessibilityIdentifier("guide.directionDiagram")
        .frame(width: 110, height: 80)
        Text(direction.movingCubies == 9 ? "Move only the front layer" : "Move the whole cube; keep all layers together")
          .font(.caption).multilineTextAlignment(.leading)
      }
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
