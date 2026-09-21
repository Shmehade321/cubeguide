import CubeSession
import SwiftUI

struct SettingsView: View {
  let controller: SessionController
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
  @State private var confirmingDelete = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Sound and feedback") {
          Toggle("Narration", isOn: preference(\.narration)).accessibilityIdentifier("settings.narration")
          Toggle("Sound effects", isOn: preference(\.effects)).accessibilityIdentifier("settings.effects")
          Toggle("Haptics", isOn: preference(\.haptics)).accessibilityIdentifier("settings.haptics")
        }.disabled(busy)
        Section("Guidance") {
          Picker("Speed", selection: preference(\.speed)) {
            Text("Slow").tag(GuideSpeed.slow)
            Text("Normal").tag(GuideSpeed.normal)
            Text("Fast").tag(GuideSpeed.fast)
          }.accessibilityIdentifier("settings.speed")
          Toggle("Show color labels", isOn: Binding(
            get: { controller.preferences.colorLabelsEnabled(differentiateWithoutColor: differentiate) },
            set: { value in var next = controller.preferences; next.showColorLabels = value; controller.savePreferences(next) }
          ))
          .disabled(differentiate)
          .accessibilityIdentifier("settings.labels")
          if differentiate { Text("Color labels stay on while Differentiate Without Color is enabled.") }
        }.disabled(busy)
        if controller.preferencesStatus == .saving { ProgressView("Saving settings…") }
        if controller.preferencesStatus == .failed {
          Section {
            Text("The settings save couldn't be confirmed. Retry to apply your change.")
            Button("Retry save") { controller.retryPreferences() }
              .accessibilityIdentifier("settings.retry")
          }
        }
        Section("Local data") {
          Button("Delete local data", role: .destructive) { confirmingDelete = true }
            .accessibilityIdentifier("settings.delete")
          Text("Removes saved colors and guidance and resets all preferences on this iPhone.")
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.accessibilityIdentifier("settings.done")
        }
      }
      .alert("Delete all local data?", isPresented: $confirmingDelete) {
        Button("Cancel", role: .cancel) {}
        Button("Delete local data", role: .destructive) {
          if controller.send(.deleteLocalData(confirmed: true)) == .accepted { dismiss() }
        }.accessibilityIdentifier("settings.delete.confirm")
      } message: {
        Text("Your saved cube and guide will be removed and settings reset to their defaults. This cannot be undone.")
      }
    }
  }
  private var busy: Bool { controller.preferencesStatus == .saving }
  private func preference<Value>(_ key: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
    Binding(get: { controller.preferences[keyPath: key] }, set: { value in
      var next = controller.preferences
      next[keyPath: key] = value
      controller.savePreferences(next)
    })
  }
}
