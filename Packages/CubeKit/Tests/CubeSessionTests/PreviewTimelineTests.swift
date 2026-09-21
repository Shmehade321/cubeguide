import CubeCore
import Testing
@testable import CubeSession

@Test("R12: static preview deadlines retain remaining hold and duration across pause and replay")
func previewTimelineRemainingDuration() {
  // A zero/fresh-duration deadline on resume would finish early or repeat the
  // full demonstration; counting paused wall time would skip the static hold.
  let cases: [(GuideOperation, GuideSpeed, Int64)] = [
    (.turn(Move(face: .front, turns: .clockwise)), .normal, 1700),
    (.turn(Move(face: .front, turns: .counterclockwise)), .slow, 2900),
    (.turn(Move(face: .front, turns: .half)), .fast, 1400),
    (.regrip(.topToward), .normal, 1700),
  ]
  for (operation, speed, total) in cases {
    var timeline = PreviewTimeline(operation: operation, speed: speed)
    #expect(timeline.remainingDuration == .milliseconds(total))
    timeline.play(at: .seconds(10))
    timeline.pause(at: .milliseconds(10200))
    #expect(timeline.remainingDuration == .milliseconds(total - 200))
    timeline.advance(to: .seconds(100))
    #expect(timeline.remainingDuration == .milliseconds(total - 200))
    timeline.play(at: .seconds(100))
    timeline.advance(to: .milliseconds(100000 + total - 201))
    #expect(timeline.remainingDuration == .milliseconds(1))
    #expect(timeline.status == .playing)
    timeline.advance(to: .milliseconds(100000 + total - 200))
    #expect(timeline.remainingDuration == .zero)
    #expect(timeline.status == .finished)
    timeline.play(at: .seconds(200), restart: true)
    #expect(timeline.remainingDuration == .milliseconds(total))
    timeline.advance(to: .milliseconds(200800))
    #expect(timeline.remainingDuration == .milliseconds(total - 800))
    timeline.advance(to: .seconds(150))
    #expect(timeline.remainingDuration == .milliseconds(total - 800))
    timeline.stop()
    #expect(timeline.remainingDuration == .milliseconds(total))
  }
}

@Test("R08/V10: preview holds before and uses specified turn/regrip durations at every speed")
func previewTimelineDurations() {
  // Removing the before hold, treating half turns as quarters, or reversing
  // the speed multiplier must fail these externally specified boundaries.
  let operations: [(GuideOperation, Int64)] = [
    (.turn(Move(face: .front, turns: .clockwise)), 1200),
    (.turn(Move(face: .front, turns: .counterclockwise)), 1200),
    (.turn(Move(face: .front, turns: .half)), 1800),
  ] + Regrip.allCases.map { (.regrip($0), 1200) }
  for (operation, normal) in operations {
    for (speed, milliseconds) in [(GuideSpeed.slow, normal * 2), (.normal, normal), (.fast, normal / 2)] {
      var timeline = PreviewTimeline(operation: operation, speed: speed)
      timeline.play(at: .seconds(10))
      #expect(timeline.status == .playing && timeline.progress == 0)
      timeline.advance(to: .milliseconds(10499))
      #expect(timeline.progress == 0)
      timeline.advance(to: .milliseconds(10500))
      #expect(timeline.progress == 0 && timeline.status == .playing)
      timeline.advance(to: .milliseconds(10500 + milliseconds / 2))
      #expect(abs(timeline.progress - 0.5) < 0.000001)
      timeline.advance(to: .milliseconds(10500 + milliseconds - 1))
      #expect(timeline.progress < 1 && timeline.status == .playing)
      timeline.advance(to: .milliseconds(10500 + milliseconds))
      #expect(timeline.progress == 1 && timeline.status == .finished)
      timeline.advance(to: .seconds(999))
      #expect(timeline.progress == 1 && timeline.status == .finished)
    }
  }
}

@Test("R08/V10: pause retains fractional preview; resume excludes paused time; replay resets hold")
func previewTimelinePauseReplay() {
  // Counting paused wall time or restarting on ordinary resume breaks this path.
  var timeline = PreviewTimeline(operation: .turn(Move(face: .front, turns: .clockwise)), speed: .normal)
  timeline.play(at: .zero)
  timeline.pause(at: .milliseconds(800))
  #expect(timeline.status == .paused && abs(timeline.progress - 0.25) < 0.000001)
  timeline.advance(to: .seconds(100))
  #expect(abs(timeline.progress - 0.25) < 0.000001)
  timeline.play(at: .seconds(100))
  timeline.advance(to: .milliseconds(100300))
  #expect(abs(timeline.progress - 0.5) < 0.000001)
  timeline.play(at: .seconds(101), restart: true)
  #expect(timeline.status == .playing && timeline.progress == 0)
  timeline.advance(to: .milliseconds(101500))
  #expect(timeline.progress == 0)
  timeline.advance(to: .milliseconds(102700))
  #expect(timeline.status == .finished && timeline.progress == 1)
}

@Test("R08/V10: obsolete time samples cannot rewind preview and stop restores idle before state")
func previewTimelineStopAndMonotonicity() {
  var timeline = PreviewTimeline(operation: .regrip(.yawLeft), speed: .normal)
  timeline.advance(to: .seconds(50))
  #expect(timeline.status == .idle && timeline.progress == 0)
  timeline.play(at: .seconds(50))
  timeline.advance(to: .milliseconds(51100))
  #expect(abs(timeline.progress - 0.5) < 0.000001)
  timeline.advance(to: .seconds(40))
  timeline.play(at: .seconds(45))
  #expect(abs(timeline.progress - 0.5) < 0.000001)
  timeline.advance(to: .milliseconds(51400))
  #expect(abs(timeline.progress - 0.75) < 0.000001)
  timeline.stop()
  timeline.advance(to: .seconds(100))
  timeline.pause(at: .seconds(101))
  #expect(timeline.status == .idle && timeline.progress == 0)
  timeline.play(at: .seconds(200))
  timeline.advance(to: .milliseconds(200500))
  #expect(timeline.progress == 0 && timeline.status == .playing)
}
