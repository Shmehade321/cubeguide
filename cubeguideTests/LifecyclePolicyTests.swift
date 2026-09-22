import CubeSession
import Testing

@testable import cubeguide

@Test("Idle timer stays disabled only during live capture or playing guidance")
func idleTimerPolicy() {
  #expect(IdleTimerPolicy.shouldDisable(scanPhase: .scanning, preview: nil))
  #expect(IdleTimerPolicy.shouldDisable(scanPhase: .freezing, preview: nil))
  #expect(IdleTimerPolicy.shouldDisable(scanPhase: nil, preview: .playing))
  #expect(!IdleTimerPolicy.shouldDisable(scanPhase: .faceReview, preview: nil))
  #expect(!IdleTimerPolicy.shouldDisable(scanPhase: nil, preview: .paused))
  #expect(!IdleTimerPolicy.shouldDisable(scanPhase: nil, preview: nil))
}
