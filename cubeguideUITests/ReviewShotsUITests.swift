import XCTest

/// Visual review + regression coverage for the rebuilt screens. Every shot is a
/// real flow assertion; attachments (.keepAlways) are the review record.
final class ReviewShotsUITests: XCTestCase {
  @MainActor
  func testRebuiltStaticScreens() {
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
    shoot(app, "review-home")

    tap(app.buttons["home.settings"])
    XCTAssertTrue(app.switches["settings.narration"].waitForExistence(timeout: 5))
    shoot(app, "review-settings")
    tap(app.buttons["settings.done"])

    tap(app.buttons["home.help"])
    XCTAssertTrue(app.staticTexts["Enter and review colors"].waitForExistence(timeout: 5))
    shoot(app, "review-help")
    tap(app.buttons["help.topic.turns"])
    XCTAssertTrue(app.staticTexts["Face turns and whole-cube turns"].waitForExistence(timeout: 5))
    shoot(app, "review-help-topic")
    tap(app.buttons["help.done"])

    tap(app.buttons["home.scan"])
    XCTAssertTrue(app.staticTexts["Scan your cube"].waitForExistence(timeout: 5))
    shoot(app, "review-scan-intro")
    tap(app.buttons["scan.cancelIntro"])
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))

    tap(app.buttons["home.practice"])
    XCTAssertTrue(app.staticTexts["practice.banner"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["editor.validate"].waitForExistence(timeout: 10))
    shoot(app, "review-practice-editor")
    tap(app.buttons["editor.validate"])
    XCTAssertTrue(app.staticTexts["Ready to solve?"].waitForExistence(timeout: 5))
    shoot(app, "review-offer")
    tap(app.buttons["practice.exit"])
    XCTAssertTrue(app.buttons["home.practice"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPracticeSolveThroughCapturesMilestones() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      tap(app.buttons["editor.home"])
    }
    tap(app.buttons["home.practice"])
    XCTAssertTrue(app.buttons["editor.validate"].waitForExistence(timeout: 10))
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    shoot(app, "review-guide-align")
    tap(app.buttons["guide.align"])
    var steps = 0
    while !app.staticTexts["The guide is finished. Check that your cube is solved."].exists {
      steps += 1
      XCTAssertLessThan(steps, 60, "Practice solution must finish")
      if steps >= 60 { break }
      let play = app.buttons["guide.play"]
      if play.exists && play.isEnabled { tap(play) }
      let ack = app.buttons["guide.acknowledge"]
      let ready = NSPredicate(format: "exists == true AND enabled == true")
      XCTAssertEqual(
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: ack)],
          timeout: 30), .completed)
      if steps == 1 { shoot(app, "review-guide-playing") }
      tap(ack)
    }
    shoot(app, "review-expected-solved")
    tap(app.buttons["completion.confirmPhysical"])
    XCTAssertTrue(
      app.staticTexts["You confirmed your cube is solved"].waitForExistence(timeout: 10))
    shoot(app, "review-completed")
    tap(app.buttons["practice.exit"])
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
        if element.isReachable || !scroll.exists { break }
        if element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
        else { scroll.swipeUp() }
      }
    }
    XCTAssertEqual(result, .completed, "Control must exist and be enabled")
    XCTAssertTrue(element.isReachable, "Control must be reachable by scrolling")
    guard result == .completed, element.isReachable else { return }
    element.tapReachable()
  }
}
