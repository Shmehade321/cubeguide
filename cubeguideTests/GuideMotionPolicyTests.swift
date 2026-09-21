@testable import CubeSession
import Testing
@testable import cubeguide

@MainActor
private final class MotionFrames: PreviewFrameSource {
  var callbacks: [@MainActor () -> Void] = []
  func start(_ update: @escaping @MainActor () -> Void) { callbacks.append(update) }
  func stop() {}
}

@MainActor
private final class MotionDeadlines: PreviewDeadlineScheduler {
  var time: Duration = .zero
  var delays: [Duration] = []
  var callbacks: [@MainActor () -> Void] = []
  var active = false
  func schedule(after delay: Duration, _ completion: @escaping @MainActor () -> Void) {
    delays.append(delay); callbacks.append(completion); active = true
  }
  func cancel() { active = false }
}

extension PresentationTests {
  @MainActor
  struct GuideMotionPolicyTests {
    @Test("R12/R09: reduced-motion guide uses static deadlines and never advances physical progress")
    func staticComposition() async throws {
      let frames = MotionFrames(), deadlines = MotionDeadlines()
      let presentation = GuidePresentation(frames: frames, now: { deadlines.time }, scheduler: deadlines)
      let practice = try await PracticeSession.start(preferences: AppPreferences(), playback: presentation)
      defer { practice.close() }
      let controller = practice.controller
      presentation.bind(controller)
      presentation.setReduceMotion(true)
      controller.send(.validateDraft); controller.send(.consent(true))
      await controller.waitForEffects()
      try #require(presentation.prepare())
      try #require(presentation.reduceMotion && presentation.scene == nil)
      let player = try #require(presentation.staticPlayer)
      controller.send(.confirmAlignment); controller.send(.play)
      try #require(deadlines.delays == [.milliseconds(2300)])
      #expect(frames.callbacks.isEmpty && !player.showingAfter)
      deadlines.time = .seconds(1)
      controller.send(.pause)
      #expect(!deadlines.active && !player.showingAfter)
      #expect(presentation.prepare() && presentation.staticPlayer === player)
      deadlines.time = .seconds(100)
      controller.send(.play)
      try #require(deadlines.delays.last == .milliseconds(1300) && deadlines.callbacks.count == 2)
      deadlines.callbacks[0]()
      #expect(controller.session.preview == .playing)
      deadlines.time = .milliseconds(101300)
      deadlines.callbacks[1]()
      #expect(player.showingAfter && controller.session.preview == .finished)
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
      #expect(frames.callbacks.isEmpty)
      #expect(controller.preferences.speed == .normal)
    }

    @Test("R12/R11: changing motion policy during playing or paused previews requires physical comparison")
    func policyInterruption() async throws {
      let frames = MotionFrames(), deadlines = MotionDeadlines()
      let presentation = GuidePresentation(frames: frames, now: { deadlines.time }, scheduler: deadlines)
      let practice = try await PracticeSession.start(preferences: AppPreferences(), playback: presentation)
      defer { practice.close() }
      let controller = practice.controller
      presentation.bind(controller)
      controller.send(.validateDraft); controller.send(.consent(true))
      await controller.waitForEffects()
      try #require(presentation.prepare())
      controller.send(.confirmAlignment); controller.send(.play)
      try #require(frames.callbacks.count == 1)
      deadlines.time = .seconds(1)
      frames.callbacks[0]()
      presentation.setReduceMotion(true)
      try #require(controller.session.phase == .resumeCheck && !controller.session.aligned)
      #expect(presentation.scene == nil)
      deadlines.time = .seconds(10)
      frames.callbacks[0]()
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
      #expect(controller.send(.compare(.before)) == .accepted)
      await controller.waitForEffects()
      if !controller.session.aligned { controller.send(.confirmAlignment) }
      controller.send(.play)
      try #require(deadlines.callbacks.count == 1)
      controller.send(.pause)
      presentation.setReduceMotion(false)
      #expect(controller.session.phase == .resumeCheck && !controller.session.aligned)
      deadlines.time = .seconds(100)
      deadlines.callbacks[0]()
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
      #expect(controller.session.preview != .finished)
      #expect(controller.preferences.speed == .normal)
    }
  }
}
