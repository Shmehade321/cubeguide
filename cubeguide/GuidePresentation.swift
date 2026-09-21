import CubeScan
import CubeSession
import Observation

/// One presentation owner per real/practice session, injected before controller creation.
@MainActor @Observable
final class GuidePresentation: GuidePlayback {
  private(set) var scene: CubeSceneModel?
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

  init(frames: any PreviewFrameSource, now: @escaping () -> Duration) {
    self.frames = frames
    self.now = now
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
    palette = nil
    preparedAction = nil
  }

  @discardableResult func prepare() -> Bool {
    guard let controller, let palette = controller.palette,
      let action = controller.session.guideProgress?.pending else { return false }
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
    player?.play(action, id: id, restart: restart, finished: finished)
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

  func pause() { player?.pause() }
  func stop() { player?.stop() }
}
