import SwiftUI

struct ScanIntroductionView: View {
  let start: () -> Void
  let enterManually: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "camera.viewfinder")
          .font(.system(size: 52))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text("Scan your cube")
          .font(.largeTitle.bold())
        Text("Show all six faces without turning any layer.")
          .font(.title3)
        Text(
          "Keep the same face on top while you move around the cube. You will review every color before CubeGuide uses the scan."
        )
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
}
