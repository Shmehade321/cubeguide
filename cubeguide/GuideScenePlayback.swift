import CubeScan
import CubeSession
import Foundation

@MainActor
protocol PreviewFrameSource: AnyObject {
  func start(_ update: @escaping @MainActor () -> Void)
  func stop()
}

/// Coordinates presentation only. Completion never acknowledges a physical action.
@MainActor
final class GuideScenePlayback: GuidePlayback {
  private let scene: CubeSceneModel
  private let palette: CenterPalette
  private let preferences: () -> AppPreferences
  private let frames: any PreviewFrameSource
  private let now: () -> Duration
  private var action: GuideAction?
  private var timeline: PreviewTimeline?
  private var frameGeneration: UUID?
  private var completion: (@MainActor @Sendable (PlaybackID) -> Void)?
  private var playbackID: PlaybackID?

  init(scene: CubeSceneModel, palette: CenterPalette, preferences: @escaping () -> AppPreferences,
    frames: any PreviewFrameSource, now: @escaping () -> Duration) {
    self.scene = scene
    self.palette = palette
    self.preferences = preferences
    self.frames = frames
    self.now = now
  }

  convenience init(scene: CubeSceneModel, palette: CenterPalette,
    preferences: @escaping () -> AppPreferences) {
    let clock = ContinuousClock()
    let origin = clock.now
    self.init(scene: scene, palette: palette, preferences: preferences,
      frames: DisplayLinkFrames(), now: { origin.duration(to: clock.now) })
  }

  func play(_ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void) {
    frames.stop()
    let resume = !restart && self.action == action && timeline?.status == .paused
    if !resume {
      let settings = preferences()
      timeline = PreviewTimeline(operation: action.operation, speed: settings.speed)
      scene.beginPreview(action, palette: palette, showColorLabels: settings.showColorLabels)
    }
    self.action = action
    playbackID = id
    completion = finished
    timeline?.play(at: now())
    let generation = UUID()
    frameGeneration = generation
    frames.start { [weak self] in self?.advance(generation: generation) }
  }

  func pause() {
    timeline?.pause(at: now())
    if let timeline { scene.samplePreview(progress: timeline.progress) }
    frameGeneration = nil
    completion = nil
    frames.stop()
  }

  func stop() {
    frameGeneration = nil
    completion = nil
    playbackID = nil
    frames.stop()
    timeline?.stop()
    timeline = nil
    action = nil
    scene.cancelPreview()
  }

  private func advance(generation: UUID) {
    guard frameGeneration == generation, var timeline else { return }
    timeline.advance(to: now())
    self.timeline = timeline
    scene.samplePreview(progress: timeline.progress)
    if timeline.status == .finished {
      frameGeneration = nil
      frames.stop()
      let callback = completion
      completion = nil
      if let playbackID { callback?(playbackID) }
    }
  }
}
