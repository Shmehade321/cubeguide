import CubeSession
import Foundation
import Observation

@MainActor
protocol PreviewDeadlineScheduler: AnyObject {
  func schedule(after delay: Duration, _ completion: @escaping @MainActor () -> Void)
  func cancel()
}

/// Static presentation timing only; no display link, renderer, or acknowledgement.
@MainActor @Observable
final class StaticGuidePlayback: GuidePlayback {
  private(set) var showingAfter = false
  @ObservationIgnored private let scheduler: any PreviewDeadlineScheduler
  @ObservationIgnored private let now: () -> Duration
  @ObservationIgnored private let preferences: () -> AppPreferences
  @ObservationIgnored private var action: GuideAction?
  @ObservationIgnored private var timeline: PreviewTimeline?
  @ObservationIgnored private var generation: UUID?
  @ObservationIgnored private var playbackID: PlaybackID?
  @ObservationIgnored private var completion: (@MainActor @Sendable (PlaybackID) -> Void)?

  init(scheduler: any PreviewDeadlineScheduler, now: @escaping () -> Duration,
    preferences: @escaping () -> AppPreferences) {
    self.scheduler = scheduler
    self.now = now
    self.preferences = preferences
  }

  func play(_ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void) {
    cancelDeadline()
    let resume = !restart && self.action == action && timeline?.status == .paused
    if !resume {
      timeline = PreviewTimeline(operation: action.operation, speed: preferences().speed)
    }
    self.action = action
    playbackID = id
    completion = finished
    showingAfter = false
    timeline?.play(at: now())
    scheduleDeadline()
  }

  func pause() {
    cancelDeadline()
    timeline?.pause(at: now())
    showingAfter = timeline?.status == .finished
    completion = nil
  }

  func stop() {
    cancelDeadline()
    timeline = nil
    action = nil
    playbackID = nil
    completion = nil
    showingAfter = false
  }

  private func cancelDeadline() {
    generation = nil
    scheduler.cancel()
  }

  private func scheduleDeadline() {
    guard let timeline else { return }
    let token = UUID()
    generation = token
    scheduler.schedule(after: timeline.remainingDuration) { [weak self] in
      self?.deadlineReached(token)
    }
  }

  private func deadlineReached(_ token: UUID) {
    guard generation == token, var timeline else { return }
    cancelDeadline()
    timeline.advance(to: now())
    self.timeline = timeline
    guard timeline.status == .finished else {
      scheduleDeadline()
      return
    }
    showingAfter = true
    let callback = completion
    completion = nil
    if let playbackID { callback?(playbackID) }
  }
}
