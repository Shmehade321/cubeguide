import CubeCore
import CubeSession
import Testing
@testable import cubeguide

@MainActor
private final class ControlledDeadline: PreviewDeadlineScheduler {
  var callbacks: [@MainActor () -> Void] = []
  var delays: [Duration] = []
  var active = false
  var time: Duration = .zero
  var finished: [PlaybackID] = []
  func schedule(after delay: Duration, _ completion: @escaping @MainActor () -> Void) {
    delays.append(delay)
    callbacks.append(completion)
    active = true
  }
  func cancel() { active = false }
}

extension PresentationTests {
  @MainActor
  struct StaticGuidePlaybackTests {
    @Test("R12: static preview stays before until deadline and excludes paused wall time")
    func pauseAndResume() throws {
      // Early endpoint selection, restarting the full duration on resume, or
      // letting a cancelled callback finish playback must fail this sequence.
      let action = try action(.clockwise)
      let scheduler = ControlledDeadline()
      let player = StaticGuidePlayback(scheduler: scheduler, now: { scheduler.time },
        preferences: { AppPreferences() })
      player.play(action, id: PlaybackID(action: action.id, sequence: 1), restart: true) {
        scheduler.finished.append($0)
      }
      try #require(scheduler.delays == [.milliseconds(1700)])
      #expect(!player.showingAfter)
      scheduler.time = .milliseconds(800)
      player.pause()
      #expect(!scheduler.active && !player.showingAfter)
      scheduler.time = .seconds(100)
      scheduler.callbacks[0]()
      #expect(scheduler.finished.isEmpty && !player.showingAfter)
      let resumed = PlaybackID(action: action.id, sequence: 2)
      player.play(action, id: resumed, restart: false) { scheduler.finished.append($0) }
      try #require(scheduler.delays == [.milliseconds(1700), .milliseconds(900)])
      scheduler.time = .milliseconds(100899)
      scheduler.callbacks[1]()
      #expect(scheduler.finished.isEmpty && !player.showingAfter)
      try #require(scheduler.delays.last == .milliseconds(1) && scheduler.callbacks.count == 3)
      scheduler.time = .milliseconds(100900)
      scheduler.callbacks[2]()
      #expect(player.showingAfter && !scheduler.active)
      #expect(scheduler.finished == [resumed])
      scheduler.callbacks[2]()
      #expect(scheduler.finished == [resumed])
      player.stop()
      #expect(!player.showingAfter)
    }

    @Test("R12: static replay, replacement and stop reject obsolete deadlines")
    func replayReplacementAndStop() throws {
      let first = try action(.half), replacement = try action(.counterclockwise)
      let scheduler = ControlledDeadline()
      let player = StaticGuidePlayback(scheduler: scheduler, now: { scheduler.time },
        preferences: { var p = AppPreferences(); p.speed = .fast; return p })
      player.play(first, id: PlaybackID(action: first.id, sequence: 1), restart: true) {
        scheduler.finished.append($0)
      }
      try #require(scheduler.delays == [.milliseconds(1400)])
      scheduler.time = .seconds(1)
      player.play(first, id: PlaybackID(action: first.id, sequence: 2), restart: true) {
        scheduler.finished.append($0)
      }
      try #require(scheduler.delays == [.milliseconds(1400), .milliseconds(1400)])
      scheduler.time = .milliseconds(1400)
      scheduler.callbacks[0]()
      #expect(scheduler.finished.isEmpty && !player.showingAfter)
      let current = PlaybackID(action: replacement.id, sequence: 3)
      player.play(replacement, id: current, restart: false) { scheduler.finished.append($0) }
      try #require(scheduler.delays.last == .milliseconds(1100) && scheduler.callbacks.count == 3)
      scheduler.time = .seconds(100)
      scheduler.callbacks[1]()
      #expect(scheduler.finished.isEmpty && !player.showingAfter)
      scheduler.callbacks[2]()
      #expect(scheduler.finished == [current] && player.showingAfter)
      player.play(first, id: PlaybackID(action: first.id, sequence: 4), restart: true) {
        scheduler.finished.append($0)
      }
      try #require(scheduler.callbacks.count == 4)
      #expect(!player.showingAfter)
      player.stop()
      scheduler.time = .seconds(200)
      scheduler.callbacks[3]()
      #expect(scheduler.finished == [current] && !player.showingAfter && !scheduler.active)
    }

    private func action(_ turns: QuarterTurns) throws -> GuideAction {
      let draft = try PracticeExample.draft()
      return try #require(GuidePlanner.actions(for: Move(face: .front, turns: turns),
        at: .identity, state: draft.canonicalFacelets(), sessionRevision: 1, moveIndex: 0).last)
    }
  }
}
