import CubeCore
import CubeScan
import CubeSession
import CubeSolver3
import SwiftUI
import UIKit

struct ContentView: View {
  @State private var controller: SessionController
  @State private var presentation: GuidePresentation?
  @State private var camera: CameraCapture?
  private let isPractice: Bool
  @State private var showingPractice = false
  @State private var replacingAfterRecovery = false
  @State private var replacing = false
  @State private var replacingWithScan = false
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
            },
            cancel: { showingScanIntroduction = false }
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
      .navigationBarTitleDisplayMode(
        controller.session.phase == .home && !showingScanIntroduction ? .large : .inline)
      .toolbar(showingScanIntroduction ? .hidden : .visible, for: .navigationBar)
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
      .alert("Replace your saved cube?", isPresented: $replacingWithScan) {
        Button("Keep current", role: .cancel) {}.accessibilityIdentifier("scanReplacement.keep")
        Button("Replace current", role: .destructive) {
          // New input starts only from Home; leaving a completed guide there keeps it saved
          // until the new scan or entry actually replaces it.
          if controller.session.phase != .home { controller.send(.cancel) }
          showingScanIntroduction = true
        }
        .accessibilityIdentifier("scanReplacement.confirm")
      } message: {
        Text("Your current cube and guide stay saved until you confirm and start the new scan.")
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
      updateIdleTimer()
    }
    .onChange(of: controller.scanWorkflow?.phase) { _, _ in updateIdleTimer() }
    .onChange(of: controller.session.preview) { _, _ in updateIdleTimer() }
    .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) {
      _ in
      guard [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) else { return }
      if controller.scanWorkflow != nil {
        controller.sendScan(.interrupt(.thermal))
      } else {
        controller.send(.background)
      }
      updateIdleTimer()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) {
      _ in
      if controller.scanWorkflow?.phase == .freezing {
        controller.sendScan(.interrupt(.orientationChanged))
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) {
      _ in
      if controller.scanWorkflow != nil {
        controller.sendScan(.interrupt(.cameraUnavailable))
      } else {
        controller.send(.background)
      }
      updateIdleTimer()
    }
    .onAppear {
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      updateIdleTimer()
    }
    .onDisappear {
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  private func updateIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
      && IdleTimerPolicy.shouldDisable(
        scanPhase: controller.scanWorkflow?.phase, preview: controller.session.preview)
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
        ScreenScaffold {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.tint.opacity(0.14))
                Image(systemName: "cube").font(.system(size: 30)).foregroundStyle(.tint)
              }
              .frame(width: 56, height: 56)
              .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text("Start with your cube").font(.title2.bold())
                Text(
                  "Enter the colors on all six faces. Your confirmed entries are saved on this iPhone."
                )
                .font(.subheadline).foregroundStyle(.secondary)
              }
            }
            CTAButton(
              "Scan cube", symbol: "camera.viewfinder", identifier: "home.scan", kind: .primary
            ) {
              if controller.session.hasWork { replacingWithScan = true }
              else { showingScanIntroduction = true }
            }
            CTAButton(
              "Enter colors", symbol: "square.grid.3x3", identifier: "home.enterColors",
              kind: .secondary
            ) {
              if controller.session.hasWork {
                replacing = true
              } else {
                reviewingInput = false
                controller.send(.startManual(replacing: false))
              }
            }
            if controller.session.hasWork {
              CTAButton(
                "Resume saved cube", symbol: "arrow.clockwise", identifier: "home.resume",
                kind: .secondary
              ) {
                controller.send(.resume)
              }
            }
          }.card()
          VStack(spacing: 0) {
            MenuRow("Practice with an example", symbol: "cube", identifier: "home.practice") {
              controller.pauseForAuxiliaryNavigation()
              showingPractice = true
            }
            Divider().padding(.leading, 40)
            MenuRow("Settings", symbol: "gearshape", identifier: "home.settings") {
              controller.pauseForAuxiliaryNavigation()
              showingSettings = true
            }
            Divider().padding(.leading, 40)
            MenuRow("Help", symbol: "questionmark.circle", identifier: "home.help", action: openHelp)
            if controller.session.hasWork {
              Divider().padding(.leading, 40)
              MenuRow(
                "Delete local data", symbol: "exclamationmark.triangle", identifier: "home.delete",
                role: .destructive
              ) {
                deleting = true
              }
            }
          }.card()
        }
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
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text("Check your entered colors")
          }
          .font(.title3.bold())
          ForEach(
            Array((controller.session.validationIssues?.items ?? []).enumerated()), id: \.offset
          ) { _, issue in
            Text(validationMessage(issue, palette: controller.palette))
          }
          Text(
            "Compare your entries with the physical cube. No colors have been changed automatically."
          )
          .foregroundStyle(.secondary)
          Text(
            relatedCells.isEmpty
              ? "This check cannot identify a specific faulty sticker. Review all entered faces."
              : "Choose Edit colors to see related stickers marked. A mark does not mean that sticker is wrong; compare all faces for missing or extra colors."
          )
          .foregroundStyle(.secondary)
          CTAButton("Edit colors", identifier: "validation.edit", kind: .primary) {
            reviewingInput = true
            controller.send(.edit)
          }
        }.card()
      }
    case .alreadySolved:
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          completionArtwork
          Text("Your entered colors are solved").font(.title3.bold())
          Text("This checks the colors you entered. Compare them with your physical cube.")
            .foregroundStyle(.secondary)
          CTAButton("Done", identifier: "completion.save", kind: .primary, action: confirmCompletion)
          CTAButton("Edit colors", identifier: "validation.edit", kind: .secondary) {
            controller.send(.edit)
          }
        }.card()
      }
    case .offer:
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").accessibilityHidden(true)
            Text("Ready to solve?")
          }
          .font(.title3.bold())
          Text(
            "Your entered colors describe a possible scrambled cube. Check that they match your cube before continuing."
          )
          .foregroundStyle(.secondary)
          CTAButton("Solve", identifier: "solve.consent", kind: .primary) {
            controller.send(.consent(true))
          }
          CTAButton("Not now", identifier: "solve.decline", kind: .secondary) {
            controller.send(.consent(false))
          }
          CTAButton("Edit colors", identifier: "validation.edit", kind: .secondary) {
            controller.send(.edit)
          }
        }.card()
      }
    case .solving:
      CalculationView { controller.send(.cancel) }
    case .solveError:
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text(
              controller.session.solveFailure == .timedOut
                ? "Calculation timed out" : "Couldn't prepare a solution")
          }
          .font(.title3.bold())
          if controller.session.solveFailure == .timedOut && !controller.session.usedExtendedAttempt
          {
            Text("You can allow one longer attempt, up to 60 seconds.")
              .foregroundStyle(.secondary)
            CTAButton("Try longer", identifier: "solve.retryLonger", kind: .primary) {
              controller.send(.retryLonger)
            }
          } else if case .resourceFailure = controller.session.solveFailure {
            Text(
              "The bundled solver resources couldn't be read. Close and restart the app. No download is required."
            )
            .foregroundStyle(.secondary)
          } else {
            Text("Your colors are saved. Check your entries or return Home.")
              .foregroundStyle(.secondary)
          }
          CTAButton("Edit colors", identifier: "validation.edit", kind: .secondary) {
            controller.send(.edit)
          }
        }.card()
      }
    case .preparingAction, .guide, .resumeCheck, .savingAcknowledgement, .storageError:
      if let presentation {
        GuideFlowView(controller: controller, presentation: presentation)
      } else {
        ContentUnavailableView("Guide unavailable", systemImage: "cube")
      }
    case .recovery:
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "questionmark.circle").accessibilityHidden(true)
            Text("Let's check your cube")
          }
          .font(.title3.bold())
          Text(
            "Your saved guide is paused. Enter every face again if your cube no longer matches it. Starting over replaces the saved guide only after you confirm."
          )
          .foregroundStyle(.secondary)
          CTAButton("Enter colors again", identifier: "recovery.manual", kind: .primary) {
            replacingAfterRecovery = true
          }
          if canScan {
            CTAButton("Scan cube again", identifier: "recovery.scan", kind: .secondary) {
              Task { await controller.startScan(purpose: .recovery) }
            }
          }
          CTAButton("Keep guide and compare again", identifier: "recovery.keep", kind: .secondary) {
            controller.send(.cancel)
          }
        }.card()
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
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          completionArtwork
          Text("The guide is finished. Check that your cube is solved.").font(.title3.bold())
          Text(
            "Look at all six physical faces. This is the expected result of the moves you acknowledged; the camera has not checked your cube."
          )
          .foregroundStyle(.secondary)
          CTAButton(
            "Yes, my cube is solved", identifier: "completion.confirmPhysical", kind: .primary,
            action: confirmCompletion
          )
          if canScan {
            CTAButton("Check with camera", identifier: "completion.scan", kind: .secondary) {
              Task { await controller.startScan(purpose: .verification) }
            }
          }
          CTAButton("Still different", identifier: "completion.mismatch", kind: .secondary) {
            controller.send(.mismatch)
          }
        }.card()
      }
    case .savingCompletion: ProgressView("Saving completion…")
    case .completionStorageError:
      failure("Couldn't save completion") { controller.send(.retryCompletionSave) }
    case .completed:
      ScreenScaffold {
        VStack(alignment: .leading, spacing: 12) {
          completionArtwork
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
            Text(completionTitle)
          }
          .font(.title3.bold())
          if canScan && controller.session.completion != .scanVerified {
            CTAButton("Check with camera", identifier: "completion.scan", kind: .secondary) {
              Task { await controller.startScan(purpose: .verification) }
            }
          }
          CTAButton("Home", identifier: "completion.home", kind: .secondary) {
            controller.send(.cancel)
          }
          if canScan {
            CTAButton(
              "Start another", symbol: "plus", identifier: "completion.startAnother",
              kind: .primary
            ) {
              replacingWithScan = true
            }
          }
        }.card()
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

  /// Practice and test hosts have no camera; never offer an action that cannot start.
  private var canScan: Bool { camera != nil }

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
      HapticFeedback.success(
        enabled: controller.preferences.haptics,
        effectsEnabled: controller.preferences.effects)
    } else {
      HapticFeedback.warning(
        enabled: controller.preferences.haptics,
        effectsEnabled: controller.preferences.effects)
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
    ScreenScaffold {
      VStack(alignment: .leading, spacing: 12) {
        ContentUnavailableView(
          title, systemImage: "exclamationmark.triangle",
          description: Text(
            "The operation couldn't be confirmed. Try again, or delete the saved cube to start fresh."
          ))
        CTAButton("Try again", kind: .primary, action: retry)
        CTAButton("Help", identifier: "failure.help", kind: .secondary, action: openHelp)
        if !isPractice {
          CTAButton("Delete local data", kind: .secondary, role: .destructive) { deleting = true }
        }
      }.card()
    }
  }
}

enum IdleTimerPolicy {
  nonisolated static func shouldDisable(scanPhase: ScanPhase?, preview: PreviewStatus?) -> Bool {
    scanPhase == .scanning || scanPhase == .freezing || preview == .playing
  }
}
