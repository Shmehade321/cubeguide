import CubeSession
import SwiftUI

struct PracticeView: View {
  let preferences: AppPreferences
  @Environment(\.dismiss) private var dismiss
  @State private var practice: PracticeSession?
  @State private var presentation = GuidePresentation()
  @State private var failed = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Text("Practice example—not your scanned cube")
          .font(.headline).accessibilityIdentifier("practice.banner")
        Button("Exit practice") {
          practice?.close()
          dismiss()
        }.accessibilityIdentifier("practice.exit")
      }.frame(maxWidth: .infinity).padding().background(.thinMaterial)
      if let practice {
        ContentView(controller: practice.controller, isPractice: true, presentation: presentation)
      } else if failed {
        ContentUnavailableView("Couldn't open practice", systemImage: "exclamationmark.triangle",
          description: Text("Your real cube is unchanged. Exit and try again."))
      } else {
        ProgressView("Opening example…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task {
      do {
        let opened = try await PracticeSession.start(preferences: preferences, playback: presentation)
        guard !Task.isCancelled else { opened.close(); return }
        presentation.bind(opened.controller)
        practice = opened
      } catch { if !Task.isCancelled { failed = true } }
    }
    .onDisappear { practice?.close() }
  }
}
