import CubeCore
import CubeScan
import SwiftUI

func validationMessage(_ issue: ValidationIssue, palette: CenterPalette?) -> String {
  func name(_ face: Face) -> String {
    palette?.colors[Int(face.rawValue)].title ?? face.title
  }
  switch issue {
  case .colorCount(let face, let actual):
    return "\(name(face)) appears \(actual) times; it needs 9 stickers."
  case .center(let face, _): return "Check the center assigned to \(face.title)."
  case .cornerIdentity:
    return "A corner has an impossible color combination. Check the three stickers of each corner."
  case .duplicateCorner: return "Two corners describe the same piece. Check the corner colors."
  case .edgeIdentity:
    return "An edge has an impossible color combination. Check the two stickers of each edge."
  case .duplicateEdge: return "Two edges describe the same piece. Check the edge colors."
  case .cornerOrientation:
    return
      "The corner orientations are inconsistent. Check the face orientation and corner entries."
  case .edgeOrientation:
    return "The edge orientations are inconsistent. Check the face orientation and edge entries."
  case .permutationParity:
    return
      "The arrangement of edges and corners is inconsistent. Check the entered colors and face orientations."
  }
}

struct CalculationView: View {
  let cancel: () -> Void
  @State private var started = ContinuousClock.now
  var body: some View {
    ScreenScaffold {
      VStack(alignment: .leading, spacing: 12) {
        ProgressView("Calculating…")
          .font(.title3.bold())
          .frame(maxWidth: .infinity, alignment: .leading)
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          Text("\(max(0, started.duration(to: .now).components.seconds)) seconds elapsed")
            .foregroundStyle(.secondary)
        }
        Text("The verified solver is searching. Your entered colors stay saved.")
          .foregroundStyle(.secondary)
        CTAButton("Cancel", identifier: "solve.cancel", kind: .secondary, action: cancel)
      }.card()
    }
  }
}
