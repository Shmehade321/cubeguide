import XCTest

/// A08 pipeline: captures the final Release-build store screenshots on the
/// required slots (6.9" + 6.5"). Driven by Scripts/capture-screenshots.sh.
///
/// Post-rebuild app journey: home → scan intro → manual entry → practice
/// editor → offer → guide → expected-solved → completed. Every shot is a real
/// flow assertion; the capture script verifies exact pixel dimensions per slot.
final class ScreenshotTests: XCTestCase {
  @MainActor
  func testCaptureStoreShots() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      tap(app.buttons["editor.home"])
    }
    if app.buttons["home.delete"].exists {
      tap(app.buttons["home.delete"])
      tap(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
      XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
    }
    shoot(app, "01-home")

    tap(app.buttons["home.scan"])
    XCTAssertTrue(app.staticTexts["Scan your cube"].waitForExistence(timeout: 5))
    shoot(app, "02-scan-intro")

    tap(app.buttons["scan.manualFallback"])
    XCTAssertTrue(app.staticTexts["Assign center colors"].waitForExistence(timeout: 5))
    shoot(app, "03-manual-entry")
    tap(app.buttons["editor.home"])
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))

    tap(app.buttons["home.practice"])
    XCTAssertTrue(app.staticTexts["practice.banner"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["editor.validate"].waitForExistence(timeout: 10))
    shoot(app, "04-practice-editor")
    tap(app.buttons["editor.validate"])
    XCTAssertTrue(app.staticTexts["Ready to solve?"].waitForExistence(timeout: 5))
    shoot(app, "05-offer")
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    shoot(app, "06-align")
    tap(app.buttons["guide.align"])
    let ack = app.buttons["guide.acknowledge"]
    let ready = NSPredicate(format: "exists == true AND enabled == true")
    var steps = 0
    while !app.staticTexts["The guide is finished. Check that your cube is solved."].exists {
      steps += 1
      XCTAssertLessThan(steps, 60, "Practice solution must finish")
      if steps >= 60 { break }
      let play = app.buttons["guide.play"]
      if play.exists && play.isEnabled { tap(play) }
      XCTAssertEqual(
        XCTWaiter.wait(
          for: [XCTNSPredicateExpectation(predicate: ready, object: ack)], timeout: 30),
        .completed)
      if steps == 1 { shoot(app, "07-guide") }
      tap(ack)
    }
    shoot(app, "08-expected-solved")
    tap(app.buttons["completion.confirmPhysical"])
    XCTAssertTrue(
      app.staticTexts["You confirmed your cube is solved"].waitForExistence(timeout: 10))
    shoot(app, "09-completed")
    tap(app.buttons["practice.exit"])
    XCTAssertTrue(app.buttons["home.practice"].waitForExistence(timeout: 5))
  }

  @MainActor private func shoot(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func tap(_ element: XCUIElement) {
    let ready = NSPredicate(format: "exists == true AND enabled == true")
    let result = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: ready, object: element)], timeout: 10)
    let app = XCUIApplication()
    if result == .completed {
      let scroll = app.scrollViews.firstMatch
      for _ in 0..<4 {
        if element.isHittable || !scroll.exists { break }
        if element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
        else { scroll.swipeUp() }
      }
    }
    XCTAssertEqual(result, .completed, "Control must exist and be enabled")
    XCTAssertTrue(element.isHittable, "Control must be reachable by scrolling")
    guard result == .completed, element.isHittable else { return }
    element.tap()
  }
}
