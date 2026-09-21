import CubeCore
import CubeScan
import CubeSession
import SwiftUI

struct ContentView: View {
  @State private var controller: SessionController
  @State private var replacing = false
  @State private var deleting = false
  @Environment(\.scenePhase) private var scenePhase

  init() {
    _controller = State(initialValue: AppDependencies().makeSessionController())
  }

  var body: some View {
    NavigationStack {
      Group {
        if controller.loadStatus == .idle || controller.loadStatus == .loading {
          ProgressView("Opening saved cube…")
        } else if controller.loadStatus == .failed {
          failure("Couldn't open your saved cube") { Task { await controller.load() } }
        } else if controller.manualFallbackStatus == .saving {
          ProgressView("Saving manual entry…")
        } else if controller.manualFallbackStatus == .failed {
          failure("Couldn't save manual entry") { controller.retryManualFallback() }
        } else if let scan = controller.pendingScan {
          CenterAssignmentView(initial: scan.draft.confirmedCenters) { palette in
            controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
          }
        } else {
          sessionContent
        }
      }
      .navigationTitle(controller.session.phase == .home ? "CubeGuide" : "Enter colors")
      .navigationBarTitleDisplayMode(controller.session.phase == .home ? .large : .inline)
      .toolbar {
        if controller.loadStatus == .ready, controller.session.phase != .home {
          ToolbarItem(placement: .topBarLeading) {
            Button("Home") { controller.send(.cancel) }
              .accessibilityIdentifier("editor.home")
              .disabled(
                [.deleting, .deletionError, .manualStartError, .draftStorageError].contains(
                  controller.session.phase))
          }
        }
      }
      .alert("Replace your saved cube?", isPresented: $replacing) {
        Button("Keep current", role: .cancel) {}.accessibilityIdentifier("replacement.keep")
        Button("Replace current", role: .destructive) {
          controller.send(.startManual(replacing: true))
        }
        .accessibilityIdentifier("replacement.confirm")
      } message: {
        Text(
          "Your current cube and guide will no longer be active. Start again only if you want to enter a different cube."
        )
      }
      .alert("Delete saved cube?", isPresented: $deleting) {
        Button("Cancel", role: .cancel) {}
        Button("Delete cube", role: .destructive) {
          controller.send(.deleteLocalData(confirmed: true))
        }
        .accessibilityIdentifier("delete.confirm")
      } message: {
        Text("This removes your saved colors and guide from this device.")
      }
    }
    .task { await controller.load() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { controller.send(.background) }
    }
  }

  @ViewBuilder private var sessionContent: some View {
    switch controller.session.phase {
    case .home:
      VStack(alignment: .leading, spacing: 24) {
        Text("Start with your cube").font(.largeTitle.bold())
        Text("Enter the colors on all six faces. Your confirmed entries are saved on this iPhone.")
        Button("Enter colors", systemImage: "square.grid.3x3") {
          if controller.session.hasWork {
            replacing = true
          } else {
            controller.send(.startManual(replacing: false))
          }
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .accessibilityIdentifier("home.enterColors")
        if controller.session.hasWork {
          Button("Resume saved cube", systemImage: "arrow.clockwise") { controller.send(.resume) }
            .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("home.resume")
          Button("Delete saved cube", role: .destructive) { deleting = true }
            .accessibilityIdentifier("home.delete")
        }
        Spacer()
      }.padding()
    case .editing, .savingDraft:
      if let draft = controller.session.draft {
        ManualEditorView(draft: draft, saving: controller.session.phase == .savingDraft) {
          controller.send(.editDraft($0))
        }
      } else {
        CenterAssignmentView(initial: nil) { controller.send(.editDraft(.centers($0))) }
      }
    case .startingManual: ProgressView("Starting your cube…")
    case .deleting: ProgressView("Deleting saved cube…")
    case .draftStorageError:
      failure("Couldn't save your colors") { controller.send(.retryDraftSave) }
    case .manualStartError:
      failure("Couldn't start a new cube") { controller.send(.retryManualStart) }
    case .deletionError:
      failure("Couldn't delete your saved cube") { controller.send(.retryDeletion) }
    default:
      ContentUnavailableView(
        "Saved guide", systemImage: "cube",
        description: Text("Your saved cube is retained. Guidance is currently unavailable."))
    }
  }

  private func failure(_ title: String, retry: @escaping () -> Void) -> some View {
    VStack(spacing: 20) {
      ContentUnavailableView(
        title, systemImage: "exclamationmark.triangle",
        description: Text(
          "The operation couldn't be confirmed. Try again, or delete the saved cube to start fresh."
        ))
      Button("Try again", action: retry).buttonStyle(.borderedProminent)
      Button("Delete saved cube", role: .destructive) { deleting = true }
    }.padding()
  }
}
