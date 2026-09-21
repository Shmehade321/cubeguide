import CubeCore
import CubeScan
import CubeSession
import CubeSolver3
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
      .navigationTitle(
        controller.session.phase == .home
          ? "CubeGuide" : (controller.session.plan == nil ? "Enter colors" : "Your cube")
      )
      .navigationBarTitleDisplayMode(controller.session.phase == .home ? .large : .inline)
      .toolbar {
        if controller.loadStatus == .ready, controller.session.phase != .home {
          ToolbarItem(placement: .topBarLeading) {
            Button("Home", action: goHome)
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
        ManualEditorView(
          draft: draft, saving: controller.session.phase == .savingDraft,
          validate: { controller.send(.validateDraft) }
        ) {
          controller.send(.editDraft($0))
        }
      } else {
        CenterAssignmentView(initial: nil) { controller.send(.editDraft(.centers($0))) }
      }
    case .invalid:
      VStack(spacing: 20) {
        Text("Check your entered colors").font(.title.bold())
        ForEach(
          Array((controller.session.validationIssues?.items ?? []).enumerated()), id: \.offset
        ) { _, issue in
          Text(validationMessage(issue, palette: controller.palette))
        }
        Text(
          "Compare your entries with the physical cube. No colors have been changed automatically.")
        Button("Edit colors") { controller.send(.edit) }
          .buttonStyle(.borderedProminent).accessibilityIdentifier("validation.edit")
      }.padding()
    case .alreadySolved:
      VStack(spacing: 20) {
        Text("Your entered colors are solved").font(.title.bold())
        Text("This checks the colors you entered. Compare them with your physical cube.")
        Button("Done") { controller.send(.confirmCompletion) }
          .buttonStyle(.borderedProminent).accessibilityIdentifier("completion.save")
        Button("Edit colors") { controller.send(.edit) }.accessibilityIdentifier("validation.edit")
      }.padding()
    case .offer:
      VStack(spacing: 20) {
        Text("Ready to solve?").font(.title.bold())
        Text(
          "Your entered colors describe a possible scrambled cube. Check that they match your cube before continuing."
        )
        Button("Solve") { controller.send(.consent(true)) }
          .buttonStyle(.borderedProminent).accessibilityIdentifier("solve.consent")
        Button("Not now") { controller.send(.consent(false)) }.accessibilityIdentifier(
          "solve.decline")
        Button("Edit colors") { controller.send(.edit) }.accessibilityIdentifier("validation.edit")
      }.padding()
    case .solving:
      CalculationView { controller.send(.cancel) }
    case .solveError:
      VStack(spacing: 20) {
        Text(
          controller.session.solveFailure == .timedOut
            ? "Calculation timed out" : "Couldn't prepare a solution"
        )
        .font(.title.bold())
        if controller.session.solveFailure == .timedOut && !controller.session.usedExtendedAttempt {
          Text("You can allow one longer attempt, up to 60 seconds.")
          Button("Try longer") { controller.send(.retryLonger) }.accessibilityIdentifier(
            "solve.retryLonger")
        } else if case .resourceFailure = controller.session.solveFailure {
          Text(
            "The bundled solver resources couldn't be read. Close and restart the app. No download is required."
          )
        } else {
          Text("Your colors are saved. Check your entries or return Home.")
        }
        Button("Edit colors") { controller.send(.edit) }.accessibilityIdentifier("validation.edit")
      }.padding()
    case .preparingAction: ProgressView("Saving your verified solution…")
    case .guide, .resumeCheck:
      VStack(spacing: 20) {
        Text("Solution verified").font(.title.bold()).accessibilityIdentifier("solve.verified")
        if let plan = controller.session.plan {
          Text(
            "\(plan.moves.count) \(plan.moves.count == 1 ? "move" : "moves") in the verified solution."
          )
          .accessibilityIdentifier("solve.moveCount")
        }
        Text(
          "The solution has been checked against your entered colors. The animated guide is not available yet."
        )
      }.padding()
    case .savingCompletion: ProgressView("Saving completion…")
    case .completionStorageError:
      failure("Couldn't save completion") { controller.send(.retryCompletionSave) }
    case .completed:
      VStack(spacing: 20) {
        Text(
          controller.session.completion == .enteredColorsSolved
            ? "Your entered colors are solved" : "You confirmed your cube is solved"
        )
        .font(.title.bold())
        Button("Home") { controller.send(.cancel) }.accessibilityIdentifier("completion.home")
      }.padding()
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

  private func goHome() {
    controller.send(.cancel)
    // Cancellation first preserves a safe resume/offer state. Exit that state without
    // acknowledging an action or granting physical alignment on a later resume.
    if [.resumeCheck, .offer].contains(controller.session.phase) {
      controller.send(.cancel)
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
