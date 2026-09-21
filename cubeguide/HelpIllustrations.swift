import CubeCore
import SwiftUI

enum HelpDiagramModel {
  struct OrientationPair: Equatable {
    let face: Face
    let top: Face
  }

  static let orientationPairs = Face.allCases.map {
    OrientationPair(face: $0, top: $0.topNeighbor)
  }
}

struct CaptureSequenceIllustration: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Six faces, one unchanged cube").font(.headline)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
        ForEach(Array(Face.allCases.enumerated()), id: \.element.rawValue) { index, face in
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
              .fill(.tint.opacity(0.16))
              .overlay { Image(systemName: "square.grid.3x3").font(.title3) }
              .frame(minWidth: 38, minHeight: 44)
            Text("\(index + 1). \(face.title)").font(.caption.bold()).lineLimit(1)
          }
        }
      }
      Text("Rotate the whole cube between pictures. Keep every layer fixed.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Capture Front, Right, Back, Left, Up and Down in order. Rotate the whole cube without turning a layer."
    )
    .accessibilityIdentifier("help.captureSequence")
  }
}

struct TurnVersusRegripIllustration: View {
  var body: some View {
    HStack(spacing: 18) {
      diagram(
        title: "Face turn", symbol: "square.3.layers.3d.top.filled", detail: "One layer moves")
      Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
      diagram(title: "Whole-cube turn", symbol: "rotate.3d", detail: "All six faces move")
    }
    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "A face turn moves one layer. A whole-cube turn changes how you hold all of the cube without moving a layer."
    )
    .accessibilityIdentifier("help.turnVsRegrip")
  }

  private func diagram(title: String, symbol: String, detail: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: symbol).font(.system(size: 42)).foregroundStyle(.tint)
      Text(title).font(.headline).multilineTextAlignment(.center)
      Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
  }
}

struct FaceOrientationIllustration: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Keep this neighbor at the top").font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
        ForEach(HelpDiagramModel.orientationPairs, id: \.face.rawValue) { pair in
          VStack(spacing: 4) {
            Text("↑ \(pair.top.title)").font(.caption.bold())
            RoundedRectangle(cornerRadius: 7)
              .fill(.tint.opacity(0.16))
              .overlay {
                VStack(spacing: 2) {
                  Image(systemName: "square.grid.3x3").font(.title2)
                  Text(pair.face.title).font(.caption)
                }
              }
              .frame(height: 64)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(pair.face.title) face, \(pair.top.title) neighbor at top")
        }
      }
    }
    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityIdentifier("help.orientationGuide")
  }
}
