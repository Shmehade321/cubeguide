import SwiftUI

struct ScanIntroductionView: View {
  let start: () -> Void
  let enterManually: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Scan your cube")
          .font(.largeTitle.bold())
        Text("Show all six faces without turning any layer.")
          .font(.title3)
        introStep(
          number: 1, title: "Hold the whole cube", symbol: "camera.viewfinder",
          detail: "Fit one complete face inside the grid and keep the named neighbor at the top.",
          identifier: "scan.intro.wholeCube")
        introStep(
          number: 2, title: "Show all six faces", symbol: "rotate.3d",
          detail: "Rotate the whole cube between pictures. Do not turn any layer.",
          identifier: "scan.intro.sixFaces")
        introStep(
          number: 3, title: "Review every color", symbol: "square.grid.3x3.fill",
          detail: "Adjust the corners and tap any color label that does not match your cube.",
          identifier: "scan.intro.review")
        Label("Camera access is requested only after you start.", systemImage: "hand.raised")
          .foregroundStyle(.secondary)
        Button("Start scanning", systemImage: "camera") {
          start()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("scan.start")
        Button("Enter colors manually", action: enterManually)
          .accessibilityIdentifier("scan.manualFallback")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
  }

  private func introStep(
    number: Int, title: String, symbol: String, detail: String, identifier: String
  ) -> some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.14))
        Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(.tint)
      }
      .frame(width: 72, height: 72)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("\(number). \(title)").font(.headline)
        Text(detail).foregroundStyle(.secondary)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifier)
  }
}
