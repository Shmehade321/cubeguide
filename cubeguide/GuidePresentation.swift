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
  @ObservationIgnored private var player: GuideScenePlayback?
  @ObservationIgnored private var palette: CenterPalette?
  @ObservationIgnored private var preparedAction: GuideAction?
  @ObservationIgnored private var differentiateWithoutColor = false

  private var effectivePreferences: AppPreferences {
    var preferences = controller?.preferences ?? AppPreferences()
    preferences.showColorLabels = preferences.colorLabelsEnabled(
      differentiateWithoutColor: differentiateWithoutColor)
    return preferences
  }

  init(frames: any PreviewFrameSource, now: @escaping () -> Duration,
    scheduler: any PreviewDeadlineScheduler = PreviewDeadline()) {
    self.frames = frames
    self.now = now
    self.scheduler = scheduler
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
  }

  @discardableResult func prepare() -> Bool {
    guard let controller, let palette = controller.palette,
      let action = controller.session.guideProgress?.pending else { return false }
    if reduceMotion {
      if preparedAction != action { staticPlayer?.stop() }
      if staticPlayer == nil {
        staticPlayer = StaticGuidePlayback(scheduler: scheduler, now: now,
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
      player = GuideScenePlayback(scene: scene, palette: palette,
        preferences: { [weak self] in self?.effectivePreferences ?? AppPreferences() },
        frames: frames, now: now)
    }
    guard let scene else { return false }
    scene.beginPreview(action, palette: palette, showColorLabels: effectivePreferences.showColorLabels)
    scene.cancelPreview()
    preparedAction = action
    return true
  }

  func play(_ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void) {
    guard controller?.session.guideProgress?.pending == action, id.action == action.id, prepare() else {
      stop()
      controller?.send(.background)
      return
    }
    if reduceMotion { staticPlayer?.play(action, id: id, restart: restart, finished: finished) }
    else { player?.play(action, id: id, restart: restart, finished: finished) }
  }
  func showComparison(after: Bool) {
    guard let controller, [.resumeCheck, .storageError].contains(controller.session.phase),
      let action = controller.session.pendingAction, let palette = controller.palette,
      prepare(), let scene else { return }
    player?.stop()
    scene.beginPreview(action, palette: palette, showColorLabels: effectivePreferences.showColorLabels)
    if after { scene.samplePreview(progress: 1) } else { scene.cancelPreview() }
  }

  func refreshLabels(differentiateWithoutColor: Bool) {
    self.differentiateWithoutColor = differentiateWithoutColor
    scene?.setColorLabels(effectivePreferences.showColorLabels)
  }

  func pause() {
    player?.pause()
    staticPlayer?.pause()
  }
  func stop() {
    player?.stop()
    staticPlayer?.stop()
  }
}
