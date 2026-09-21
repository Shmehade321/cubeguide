import XCTest

final class GuideUITests: XCTestCase {
  @MainActor
  func testAnimatedDirectionDoesNotCoverCube() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tap(app.buttons["editor.home"]) }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    let diagram = app.descendants(matching: .any)["guide.directionDiagram"].firstMatch
    XCTAssertTrue(diagram.waitForExistence(timeout: 5))
    let cube = app.descendants(matching: .any)["guide.animatedCube"].firstMatch
    XCTAssertTrue(cube.exists)
    XCTAssertFalse(app.descendants(matching: .any)["guide.staticCube"].firstMatch.exists)
    XCTAssertFalse(cube.frame.intersects(diagram.frame))
    let progress = app.staticTexts["guide.progress"].label
    capture(app, name: "Animated guide separate direction before")
    tap(app.buttons["guide.align"])
    tap(app.buttons["guide.play"])
    tap(app.buttons["guide.pause"])
    XCTAssertFalse(cube.frame.intersects(diagram.frame))
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    capture(app, name: "Animated guide separate direction paused")
    tap(app.buttons["practice.exit"])
  }

  @MainActor
  func testGuideRendersSavedLabelChoice() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tap(app.buttons["editor.home"]) }
    for visible in [false, true] {
      tap(app.buttons["home.settings"])
      let control = app.switches["settings.labels"]
      let ready = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: control)], timeout: 10), .completed)
      let wanted = visible ? "1" : "0"
      if control.value as? String != wanted {
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
      }
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@ AND enabled == true", wanted), object: control)], timeout: 10), .completed)
      tap(app.buttons["settings.done"])
      tap(app.buttons["home.practice"])
      tap(app.buttons["editor.validate"])
      tap(app.buttons["solve.consent"])
      XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
      tap(app.buttons["guide.align"])
      let progress = app.staticTexts["guide.progress"].label
      tap(app.buttons["guide.play"])
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == true"), object: app.buttons["guide.acknowledge"])], timeout: 10), .completed)
      XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
      capture(app, name: visible ? "Guide color labels visible" : "Guide color labels hidden")
      tap(app.buttons["practice.exit"])
    }
  }

  @MainActor
  func testPracticeGuideRequiresAlignmentAndExplicitAcknowledgement() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tap() }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    tap(app.buttons["guide.align"])
    let progress = app.staticTexts["guide.progress"].label
    tap(app.buttons["guide.play"])
    XCTAssertFalse(app.buttons["guide.acknowledge"].isEnabled)
    let finished = NSPredicate(format: "enabled == true")
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished,
      object: app.buttons["guide.acknowledge"])], timeout: 10), .completed)
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    tap(app.buttons["guide.replay"])
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished,
      object: app.buttons["guide.acknowledge"])], timeout: 10), .completed)
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Practice guide expected after preview"
    image.lifetime = .keepAlways
    add(image)
    tap(app.buttons["guide.acknowledge"])
    let advanced = NSPredicate(format: "label != %@", progress)
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advanced,
      object: app.staticTexts["guide.progress"])], timeout: 10), .completed)
    tap(app.buttons["editor.home"])
    tap(app.buttons["practice.resume"])
    XCTAssertTrue(app.buttons["guide.matchesBefore"].waitForExistence(timeout: 5))
    let resumedProgress = app.staticTexts["guide.progress"].label
    tap(app.buttons["guide.showAfter"])
    XCTAssertEqual(app.staticTexts["guide.progress"].label, resumedProgress)
    XCTAssertTrue(app.staticTexts["Expected after this action"].exists)
    tap(app.buttons["guide.matchesAfter"])
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label != %@", resumedProgress),
      object: app.staticTexts["guide.progress"])], timeout: 10), .completed)
    tap(app.buttons["practice.exit"])
    XCTAssertTrue(app.buttons["home.practice"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testUncertainGuideCanKeepOrReplaceWithManualInput() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tap(app.buttons["editor.home"]) }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    tap(app.buttons["guide.mismatch"])
    tap(app.buttons["recovery.keep"])
    app.scrollViews.firstMatch.swipeUp()
    tap(app.buttons["guide.uncertain"])
    tap(app.buttons["recovery.manual"])
    tap(app.alerts.buttons.matching(identifier: "recovery.cancelReplacement").firstMatch)
    XCTAssertTrue(app.buttons["recovery.keep"].exists)
    capture(app, name: "Recovery retains guide until replacement")
    tap(app.buttons["recovery.manual"])
    tap(app.alerts.buttons.matching(identifier: "recovery.confirmReplacement").firstMatch)
    XCTAssertTrue(app.staticTexts["Assign center colors"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["practice.banner"].exists)
    tap(app.buttons["practice.exit"])
  }

  @MainActor
  func testGuideCompletionRequiresSeparatePhysicalConfirmation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tap(app.buttons["editor.home"]) }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    tap(app.buttons["guide.align"])
    // The real planner can emit up to 90 actions; do not assume an optimal solution.
    for _ in 0..<90 {
      if app.buttons["completion.confirmPhysical"].exists { break }
      tap(app.buttons["guide.play"])
      tap(app.buttons["guide.acknowledge"])
    }
    XCTAssertTrue(app.buttons["completion.confirmPhysical"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["The guide is finished. Check that your cube is solved."].exists)
    XCTAssertFalse(app.staticTexts["You confirmed your cube is solved"].exists)
    capture(app, name: "Expected solved requires physical confirmation")
    tap(app.buttons["editor.home"])
    tap(app.buttons["practice.resume"])
    XCTAssertTrue(app.buttons["completion.confirmPhysical"].exists)
    XCTAssertFalse(app.staticTexts["You confirmed your cube is solved"].exists)
    tap(app.buttons["completion.confirmPhysical"])
    XCTAssertTrue(app.staticTexts["You confirmed your cube is solved"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["All six scanned faces are solved."].exists)
    tap(app.buttons["completion.home"])
    tap(app.buttons["practice.resume"])
    XCTAssertTrue(app.staticTexts["You confirmed your cube is solved"].exists)
    tap(app.buttons["practice.exit"])
  }

  @MainActor private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func tap(_ element: XCUIElement) {
    let ready = NSPredicate(format: "exists == true AND enabled == true")
    let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)], timeout: 10)
    let app = XCUIApplication()
    if result == .completed {
      // Longer captions and system navigation chrome can move controls below
      // the viewport. Scroll the real guide instead of waiting for it to shrink.
      let scroll = app.scrollViews.firstMatch
      for _ in 0..<4 {
        if element.isHittable || !scroll.exists { break }
        if element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
        else { scroll.swipeUp() }
      }
    }
    if result != .completed || !element.isHittable {
      capture(app, name: "Unavailable guide control")
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Unavailable guide control accessibility hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertEqual(result, .completed, "Guide control must exist and be enabled")
    XCTAssertTrue(element.isHittable, "Guide control must be reachable by scrolling")
    guard result == .completed, element.isHittable else { return }
    element.tap()
  }
}
