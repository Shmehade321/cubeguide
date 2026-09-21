import Testing
import XCTest
@testable import cubeguide

extension PresentationTests {
  @MainActor
  struct PreviewDeadlineTests {
    @Test("R12/R18: production deadline fires once after its delay")
    func delivery() async {
      let scheduler = PreviewDeadline()
      defer { scheduler.cancel() }
      let clock = ContinuousClock(), started = ContinuousClock.now
      let delivered = XCTestExpectation(description: "Static endpoint deadline")
      let duplicate = XCTestExpectation(description: "Repeated endpoint callback")
      duplicate.isInverted = true
      var count = 0
      scheduler.schedule(after: .milliseconds(50)) {
        count += 1
        #expect(started.duration(to: clock.now) >= .milliseconds(50))
        if count == 1 { delivered.fulfill() } else { duplicate.fulfill() }
      }
      #expect(await XCTWaiter.fulfillment(of: [delivered], timeout: 2) == .completed)
      #expect(await XCTWaiter.fulfillment(of: [duplicate], timeout: 0.15) == .completed)
      #expect(count == 1)
    }

    @Test("R12/R18: cancelled, replaced and released deadlines never deliver")
    func cancellationAndRelease() async {
      var scheduler: PreviewDeadline? = PreviewDeadline()
      weak var released = scheduler
      let obsolete = XCTestExpectation(description: "Obsolete deadline")
      obsolete.isInverted = true
      let replacement = XCTestExpectation(description: "Current deadline")
      scheduler?.schedule(after: .milliseconds(20)) { obsolete.fulfill() }
      scheduler?.cancel()
      scheduler?.schedule(after: .milliseconds(20)) { obsolete.fulfill() }
      scheduler?.schedule(after: .zero) { replacement.fulfill() }
      #expect(await XCTWaiter.fulfillment(of: [replacement], timeout: 2) == .completed)
      scheduler?.schedule(after: .milliseconds(20)) { obsolete.fulfill() }
      scheduler = nil
      #expect(released == nil)
      #expect(await XCTWaiter.fulfillment(of: [obsolete], timeout: 0.15) == .completed)
    }
  }
}
