import CubeCore
import CubeScan
import CubeSession
import CubeSolver3
import SwiftUI

struct ContentView: View {
  @State private var controller: SessionController
  @State private var presentation: GuidePresentation?
  @State private var camera: CameraCapture?
  private let isPractice: Bool
  @State private var showingPractice = false
  @State private var replacingAfterRecovery = false
  @State private var replacing = false
  @State private var deleting = false
  @State private var reviewingInput = false
  @State private var showingHelp = false
  @State private var showingSettings = false
  @State private var showingScanIntroduction = false
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let presentation = GuidePresentation()
    let camera = CameraCapture()
    let controller = AppDependencies().makeSessionController(playback: presentation, camera: camera)
    presentation.bind(controller)
    _controller = State(initialValue: controller)
    _presentation = State(initialValue: presentation)
    _camera = State(initialValue: camera)
    isPractice = false
  }
  init(controller: SessionController, isPractice: Bool, presentation: GuidePresentation? = nil) {
    _presentation = State(initialValue: presentation)
    _controller = State(initialValue: controller)
    _camera = State(initialValue: nil)
    self.isPractice = isPractice
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
        } else if showingScanIntroduction {
          ScanIntroductionView(
            start: {
              showingScanIntroduction = false
              Task {
                await controller.startScan(
                  purpose: .newCube,
                  replacing: controller.session.hasWork
                )
              }
            },
            enterManually: {
              showingScanIntroduction = false
              reviewingInput = false
              controller.send(.startManual(replacing: controller.session.hasWork))
            }
          )
        } else if controller.scanWorkflow != nil, let camera {
          ScanFlowView(controller: controller, camera: camera)
        } else if let scan = controller.pendingScan {
          CenterAssignmentView(initial: scan.draft.confirmedCenters) { palette in
            controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
          }
        } else {
          sessionContent
        }
      }
      .navigationTitle(
        isPractice
          ? "Practice"
          : controller.session.phase == .home
            ? "CubeGuide" : (controller.session.plan == nil ? "Enter colors" : "Your cube")
      )
      .navigationBarTitleDisplayMode(controller.session.phase == .home ? .large : .inline)
      .toolbar {
        if controller.loadStatus == .ready, controller.session.phase != .home {
          ToolbarItemGroup(placement: .topBarTrailing) {
            if !isPractice {
              Button("Settings", systemImage: "gearshape") {
                controller.pauseForAuxiliaryNavigation()
                showingSettings = true
              }.accessibilityIdentifier("navigation.settings")
            }
            Button("Help", systemImage: "questionmark.circle", action: openHelp)
              .accessibilityIdentifier("navigation.help")
          }
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
          reviewingInput = false
          controller.send(.startManual(replacing: true))
        }
        .accessibilityIdentifier("replacement.confirm")
      } message: {
        Text(
          "Your current cube and guide will no longer be active. Start again only if you want to enter a different cube."
        )
      }
      .alert("Delete all local data?", isPresented: $deleting) {
        Button("Cancel", role: .cancel) {}
        Button("Delete local data", role: .destructive) {
          controller.send(.deleteLocalData(confirmed: true))
        }
        .accessibilityIdentifier("delete.confirm")
      } message: {
        Text("This removes your saved colors and guide and resets all preferences on this device.")
      }
    }
    .fullScreenCover(isPresented: $showingPractice) {
      PracticeView(preferences: controller.preferences)
    }
    .sheet(isPresented: $showingHelp) { HelpView() }
    .sheet(isPresented: $showingSettings) { SettingsView(controller: controller) }
    .task { await controller.load() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { controller.send(.background) }
    }
  }

  @ViewBuilder private var sessionContent: some View {
    switch controller.session.phase {
    case .home:
      if isPractice {
        VStack(spacing: 20) {
          Text("Your example stays here until you exit practice.")
          if controller.session.hasWork {
            Button("Resume example") { controller.send(.resume) }
              .accessibilityIdentifier("practice.resume")
          }
        }.padding()
      } else {
        VStack(alignment: .leading, spacing: 24) {
          Text("Start with your cube").font(.largeTitle.bold())
          Text(
            "Enter the colors on all six faces. Your confirmed entries are saved on this iPhone.")
          Button("Enter colors", systemImage: "square.grid.3x3") {
            if controller.session.hasWork {
              replacing = true
            } else {
              reviewingInput = false
              controller.send(.startManual(replacing: false))
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .accessibilityIdentifier("home.enterColors")
          Button("Scan cube", systemImage: "camera.viewfinder") {
            showingScanIntroduction = true
          }
          .buttonStyle(.bordered).controlSize(.large)
          .accessibilityIdentifier("home.scan")
          if controller.session.hasWork {
            Button("Resume saved cube", systemImage: "arrow.clockwise") { controller.send(.resume) }
              .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("home.resume")
            Button("Delete local data", role: .destructive) { deleting = true }
              .accessibilityIdentifier("home.delete")
          }
          Button("Practice with an example", systemImage: "cube") {
            controller.pauseForAuxiliaryNavigation()
            showingPractice = true
          }.accessibilityIdentifier("home.practice")
          Button("Settings", systemImage: "gearshape") {
            controller.pauseForAuxiliaryNavigation()
            showingSettings = true
          }.accessibilityIdentifier("home.settings")
          Button("Help", systemImage: "questionmark.circle", action: openHelp)
            .accessibilityIdentifier("home.help")
          Spacer()
        }.padding()
      }
    case .editing, .savingDraft:
      if let draft = controller.session.draft {
        ManualEditorView(
          draft: draft,
          showColorLabels: controller.preferences.colorLabelsEnabled(
            differentiateWithoutColor: differentiate),
          saving: controller.session.phase == .savingDraft,
          reviewCells: reviewingInput ? relatedCells : [],
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
        Text(
          relatedCells.isEmpty
            ? "This check cannot identify a specific faulty sticker. Review all entered faces."
            : "Choose Edit colors to see related stickers marked. A mark does not mean that sticker is wrong; compare all faces for missing or extra colors."
        )
        Button("Edit colors") {
          reviewingInput = true
          controller.send(.edit)
        }
        .buttonStyle(.borderedProminent).accessibilityIdentifier("validation.edit")
      }.padding()
    case .alreadySolved:
      ScrollView {
        VStack(spacing: 20) {
          completionArtwork
          Text("Your entered colors are solved").font(.title.bold())
          Text("This checks the colors you entered. Compare them with your physical cube.")
          Button("Done", action: confirmCompletion)
            .buttonStyle(.borderedProminent).accessibilityIdentifier("completion.save")
          Button("Edit colors") { controller.send(.edit) }.accessibilityIdentifier(
            "validation.edit")
        }.padding()
      }
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
    case .preparingAction, .guide, .resumeCheck, .savingAcknowledgement, .storageError:
      if let presentation {
        GuideFlowView(controller: controller, presentation: presentation)
      } else {
        ContentUnavailableView("Guide unavailable", systemImage: "cube")
      }
    case .recovery:
      ScrollView {
        VStack(spacing: 20) {
          Text("Let's check your cube").font(.title.bold())
          Text(
            "Your saved guide is paused. Enter every face again if your cube no longer matches it. Starting over replaces the saved guide only after you confirm."
          )
          Button("Enter colors again") { replacingAfterRecovery = true }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("recovery.manual")
          Button("Scan cube again") {
            Task { await controller.startScan(purpose: .recovery) }
          }.accessibilityIdentifier("recovery.scan")
          Button("Keep guide and compare again") { controller.send(.cancel) }
            .accessibilityIdentifier("recovery.keep")
        }.padding()
      }
      .alert("Replace your saved guide?", isPresented: $replacingAfterRecovery) {
        Button("Keep current", role: .cancel) {}.accessibilityIdentifier(
          "recovery.cancelReplacement")
        Button("Replace and enter colors", role: .destructive) {
          reviewingInput = false
          controller.send(.startManual(replacing: true))
        }.accessibilityIdentifier("recovery.confirmReplacement")
      } message: {
        Text(
          "You will choose all six centers and enter your cube again. The previous instructions will no longer be active."
        )
      }
    case .savingRecovery: ProgressView("Pausing your saved guide…")
    case .recoveryStorageError:
      failure("Couldn't save recovery") { controller.send(.retryRecoverySave) }
    case .expectedSolved:
      ScrollView {
        VStack(spacing: 20) {
          completionArtwork
          Text("The guide is finished. Check that your cube is solved.").font(.title.bold())
          Text(
            "Look at all six physical faces. This is the expected result of the moves you acknowledged; the camera has not checked your cube."
          )
          Button("Yes, my cube is solved", action: confirmCompletion)
            .buttonStyle(.borderedProminent).accessibilityIdentifier("completion.confirmPhysical")
          Button("Check with camera") {
            Task { await controller.startScan(purpose: .verification) }
          }.accessibilityIdentifier("completion.scan")
          Button("Still different") { controller.send(.mismatch) }
            .accessibilityIdentifier("completion.mismatch")
        }.padding()
      }
    case .savingCompletion: ProgressView("Saving completion…")
    case .completionStorageError:
      failure("Couldn't save completion") { controller.send(.retryCompletionSave) }
    case .completed:
      ScrollView {
        VStack(spacing: 20) {
          completionArtwork
          Text(completionTitle)
            .font(.title.bold())
          if controller.session.completion != .scanVerified {
            Button("Check with camera") {
              Task { await controller.startScan(purpose: .verification) }
            }.accessibilityIdentifier("completion.scan")
          }
          Button("Home") { controller.send(.cancel) }.accessibilityIdentifier("completion.home")
        }.padding()
      }
    case .startingManual: ProgressView("Starting your cube…")
    case .deleting: ProgressView("Deleting saved cube…")
    case .draftStorageError:
      failure("Couldn't save your colors") { controller.send(.retryDraftSave) }
    case .manualStartError:
      failure("Couldn't start a new cube") { controller.send(.retryManualStart) }
    case .deletionError:
      failure("Couldn't delete your saved cube") { controller.send(.retryDeletion) }
    }
  }

  @ViewBuilder
  private var completionArtwork: some View {
    if let palette = controller.palette,
      let state = controller.session.guideProgress?.state
        ?? controller.session.confirmedCube?.facelets
    {
      CompletionArtwork(
        state: state, palette: palette,
        pose: controller.session.guideProgress?.pose ?? .identity,
        showColorLabels: controller.preferences.colorLabelsEnabled(
          differentiateWithoutColor: differentiate))
    }
  }

  private func openHelp() {
    controller.pauseForAuxiliaryNavigation()
    showingHelp = true
  }

  private var completionTitle: String {
    switch controller.session.completion {
    case .enteredColorsSolved: "Your entered colors are solved"
    case .userConfirmed: "You confirmed your cube is solved"
    case .scanVerified: "Camera verified all six faces"
    case nil: "Your cube is solved"
    }
  }

  private func confirmCompletion() {
    let result = controller.send(.confirmCompletion)
    if result == .accepted {
      HapticFeedback.success(enabled: controller.preferences.haptics)
    } else {
      HapticFeedback.warning(enabled: controller.preferences.haptics)
    }
  }

  private var relatedCells: Set<Int> {
    guard let draft = controller.session.draft,
      let faces = try? draft.canonicalFacelets()
    else { return [] }
    return Set(CubeValidation.reviewCells(in: faces))
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
      Button("Help", action: openHelp).accessibilityIdentifier("failure.help")
      if !isPractice { Button("Delete local data", role: .destructive) { deleting = true } }
    }.padding()
  }
}
