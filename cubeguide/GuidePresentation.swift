import CubeCore
import CubeScan
import CubeSession
import Observation

/// One presentation owner per real/practice session, injected before controller creation.
@MainActor @Observable
final class GuidePresentation: GuidePlayback {
  private(set) var scene: CubeSceneModel?
  private(set) var reduceMotion = false
  private(set) var staticPlayer: StaticGuidePlayback?
  var previewDescription: String {
    switch controller?.session.preview {
    case .some(.playing): "Demonstration in progress"
    case .some(.paused): "Paused demonstration"
    case .some(.finished): "Expected after this action"
    default: "Before this action"
    }
  }
  @ObservationIgnored private weak var controller: SessionController?
  @ObservationIgnored private let frames: any PreviewFrameSource
  @ObservationIgnored private let now: () -> Duration
  @ObservationIgnored private let scheduler: any PreviewDeadlineScheduler
  @ObservationIgnored private let narration: any InstructionAudio
  @ObservationIgnored private var player: GuideScenePlayback?
  @ObservationIgnored private var palette: CenterPalette?
  @ObservationIgnored private var preparedAction: GuideAction?
  @ObservationIgnored private var differentiateWithoutColor = false
  @ObservationIgnored private var narrationGeneration: UInt64 = 0
  @ObservationIgnored private var animationStartedForAction: ActionID?

  private var effectivePreferences: AppPreferences {
    var preferences = controller?.preferences ?? AppPreferences()
    preferences.showColorLabels = preferences.colorLabelsEnabled(
      differentiateWithoutColor: differentiateWithoutColor)
    return preferences
  }

  init(
    frames: any PreviewFrameSource, now: @escaping () -> Duration,
    scheduler: any PreviewDeadlineScheduler = PreviewDeadline(),
    narration: any InstructionAudio = AudioCoordinator()
  ) {
    self.frames = frames
    self.now = now
    self.scheduler = scheduler
    self.narration = narration
    narration.setInterruptionHandler { [weak self] in
      guard let self, self.controller?.session.preview == .playing else { return }
      self.controller?.send(.pause)
    }
  }

  func setReduceMotion(_ enabled: Bool) {
    guard reduceMotion != enabled else { return }
    if let preview = controller?.session.preview, preview == .playing || preview == .paused {
      controller?.send(.background)
    }
    stop()
    reduceMotion = enabled
    scene = nil
    player = nil
    staticPlayer = nil
    preparedAction = nil
    animationStartedForAction = nil
    prepare()
  }

  convenience init() {
    let clock = ContinuousClock()
    let origin = clock.now
    self.init(frames: DisplayLinkFrames(), now: { origin.duration(to: clock.now) })
  }

  func bind(_ controller: SessionController) {
    guard self.controller !== controller else { return }
    stop()
    self.controller = controller
    scene = nil
    player = nil
    staticPlayer = nil
    palette = nil
    preparedAction = nil
    animationStartedForAction = nil
  }

  @discardableResult func prepare() -> Bool {
    guard let controller, let palette = controller.palette,
      let action = controller.session.guideProgress?.pending
    else { return false }
    if reduceMotion {
      if preparedAction != action { staticPlayer?.stop() }
      if staticPlayer == nil {
        staticPlayer = StaticGuidePlayback(
          scheduler: scheduler, now: now,
          preferences: { [weak self] in self?.effectivePreferences ?? AppPreferences() })
      }
      self.palette = palette
      preparedAction = action
      return true
    }
    if preparedAction == action, self.palette == palette, let scene {
      scene.setColorLabels(effectivePreferences.showColorLabels)
      return true
    }
    player?.stop()
    if self.palette != palette || scene == nil {
      let scene = CubeSceneModel(draft: ManualDraft(palette: palette))
      self.scene = scene
      self.palette = palette
      player = GuideScenePlayback(
        scene: scene, palette: palette,
        preferences: { [weak self] in self?.effectivePreferences ?? AppPreferences() },
        frames: frames, now: now)
    }
    guard let scene else { return false }
    scene.beginPreview(
      action, palette: palette, showColorLabels: effectivePreferences.showColorLabels)
    scene.cancelPreview()
    preparedAction = action
    return true
  }

  func play(
    _ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void
  ) {
    guard controller?.session.guideProgress?.pending == action, id.action == action.id,
      prepare(), let palette
    else {
      stop()
      controller?.send(.background)
      return
    }
    narrationGeneration &+= 1
    let generation = narrationGeneration
    let startAnimation: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self, self.narrationGeneration == generation,
        self.controller?.session.guideProgress?.pending == action
      else { return }
      self.animationStartedForAction = action.id
      if self.reduceMotion {
        self.staticPlayer?.play(action, id: id, restart: restart, finished: finished)
      } else {
        self.player?.play(action, id: id, restart: restart, finished: finished)
      }
    }
    if !restart, animationStartedForAction == action.id {
      startAnimation()
    } else {
      let pose = action.fromPose
      let color: (Face) -> CubeColor = {
        palette.colors[Int(pose.canonicalFace(at: $0).rawValue)]
      }
      let phrases = PhraseCatalog.pose(
        front: color(.front), top: color(.up), right: color(.right))
        + [PhraseCatalog.phrase(for: action.operation)]
      playSequence(
        phrases[...], enabled: effectivePreferences.narration,
        generation: generation, finished: startAnimation)
    }
  }

  private func playSequence(
    _ phrases: ArraySlice<Phrase>, enabled: Bool, generation: UInt64,
    finished: @escaping @MainActor @Sendable () -> Void
  ) {
    guard narrationGeneration == generation else { return }
    guard let phrase = phrases.first else {
      finished()
      return
    }
    narration.play(phrase, enabled: enabled) { [weak self] in
      guard let self, self.narrationGeneration == generation else { return }
      self.playSequence(
        phrases.dropFirst(), enabled: enabled, generation: generation, finished: finished)
    }
  }
  func showComparison(after: Bool) {
    guard let controller, [.resumeCheck, .storageError].contains(controller.session.phase),
      let action = controller.session.pendingAction, let palette = controller.palette,
      prepare(), let scene
    else { return }
    player?.stop()
    scene.beginPreview(
      action, palette: palette, showColorLabels: effectivePreferences.showColorLabels)
    if after { scene.samplePreview(progress: 1) } else { scene.cancelPreview() }
  }

  func refreshLabels(differentiateWithoutColor: Bool) {
    self.differentiateWithoutColor = differentiateWithoutColor
    scene?.setColorLabels(effectivePreferences.showColorLabels)
  }

  func pause() {
    narrationGeneration &+= 1
    narration.pause()
    player?.pause()
    staticPlayer?.pause()
  }
  func stop() {
    narrationGeneration &+= 1
    narration.stop()
    player?.stop()
    staticPlayer?.stop()
  }
}
