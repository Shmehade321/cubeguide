import CubeSession
import SwiftUI

struct PracticeView: View {
  let preferences: AppPreferences
  @Environment(\.dismiss) private var dismiss
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var practice: PracticeSession?
  @State private var presentation = GuidePresentation()
  @State private var failed = false

  private var bannerLayout: AnyLayout {
    verticalSizeClass == .compact
      ? AnyLayout(HStackLayout(spacing: 16))
      : AnyLayout(VStackLayout(spacing: 8))
  }

  var body: some View {
    VStack(spacing: 0) {
      bannerLayout {
        Text("Practice example—not your scanned cube")
          .font(verticalSizeClass == .compact ? .caption : .headline)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("practice.banner")
        Button("Exit practice") {
          practice?.close()
          dismiss()
        }.accessibilityIdentifier("practice.exit")
          .font(verticalSizeClass == .compact ? .caption : .body)
          .fixedSize(horizontal: verticalSizeClass == .compact, vertical: true)
          .frame(minHeight: 44)
      }.frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, verticalSizeClass == .compact ? 8 : 16)
        .background(.thinMaterial)
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
