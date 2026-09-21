import XCTest

final class ReduceMotionUITests: XCTestCase {
  @MainActor
  func testLandscapePracticeLeavesRoomForACompleteGuideControl() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let original = try setReduceMotion(true, settings: settings)
    addTeardownBlock { @MainActor in
      try self.setReduceMotion(original, settings: settings)
      settings.terminate()
    }
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tap() }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    XCUIDevice.shared.orientation = .landscapeLeft
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.frame.width > app.frame.height &&
        app.navigationBars["Practice"].frame.width >= app.frame.width - 2 &&
        app.scrollViews.firstMatch.frame.width >= app.frame.width - 2
    }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    capture(app, "Landscape practice control space")
    let contentTop = max(app.scrollViews.firstMatch.frame.minY,
      app.navigationBars["Practice"].frame.maxY)
    XCTAssertGreaterThanOrEqual(app.frame.maxY - contentTop, app.buttons["guide.align"].frame.height,
      "Practice context must leave enough space to read a complete guide control")
    XCTAssertTrue(app.otherElements["guide.staticCube"].exists)
    XCTAssertLessThanOrEqual(app.otherElements["guide.staticCube"].frame.height, app.frame.maxY - contentTop,
      "The complete comparison cube must fit within the visible content area")
    XCTAssertEqual(app.staticTexts["practice.banner"].label, "Practice example—not your scanned cube")
  }

  @MainActor
  func testSystemReduceMotionShowsStaticGuideWithoutAdvancingProgress() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let original = try setReduceMotion(true, settings: settings)
    addTeardownBlock { @MainActor in
      try self.setReduceMotion(original, settings: settings)
      settings.terminate()
    }
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tap() }
    tap(app.buttons["home.practice"])
    tap(app.buttons["editor.validate"])
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.otherElements["guide.staticCube"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Static before this action"].exists)
    XCTAssertTrue(app.otherElements["guide.directionDiagram"].exists)
    XCTAssertFalse(app.otherElements["guide.staticCube"].frame.intersects(
      app.otherElements["guide.directionDiagram"].frame), "Direction cue must not obscure comparison stickers")
    capture(app, "Reduce Motion before")
    revealAndTap(app.buttons["guide.align"], in: app)
    // Even at the largest accessibility size, these short labels must fit
    // within two lines plus normal control padding, not one glyph per line.
    for identifier in ["guide.play", "guide.pause", "guide.replay"] {
      XCTAssertLessThanOrEqual(app.buttons[identifier].frame.height, 120,
        "Playback labels must remain readable at the selected text size")
    }
    let progress = app.staticTexts["guide.progress"].label
    revealAndTap(app.buttons["guide.play"], in: app)
    XCTAssertTrue(app.staticTexts["Static expected after this action"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    capture(app, "Reduce Motion expected after")
    revealAndTap(app.buttons["guide.replay"], in: app)
    revealAndTap(app.buttons["guide.pause"], in: app)
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.buttons["guide.matchesBefore"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    revealAndTap(app.buttons["guide.showAfter"], in: app)
    XCTAssertTrue(app.staticTexts["Static expected after this action"].exists)
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    revealAndTap(app.buttons["guide.showBefore"], in: app)
    XCTAssertTrue(app.staticTexts["Static before this action"].exists)
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    revealAndTap(app.buttons["guide.matchesBefore"], in: app)
    revealAndTap(app.buttons["guide.play"], in: app)
    XCTAssertTrue(app.staticTexts["Static expected after this action"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["guide.progress"].label, progress)
    revealAndTap(app.buttons["guide.acknowledge"], in: app)
    let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", progress),
      object: app.staticTexts["guide.progress"])
    XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
    XCTAssertTrue(app.staticTexts["Static before this action"].exists)
    let portraitProgress = app.staticTexts["guide.progress"].label
    XCUIDevice.shared.orientation = .landscapeLeft
    let landscapeLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let window = app.frame
      let navigation = app.navigationBars["Practice"].frame
      let scroll = app.scrollViews.firstMatch.frame
      return window.width > window.height && navigation.width >= window.width - 2 &&
        scroll.width >= window.width - 2 && scroll.minY >= 0
    }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [landscapeLayout], timeout: 5), .completed)
    XCTAssertGreaterThan(app.frame.width, app.frame.height)
    revealAndTap(app.buttons["guide.play"], in: app)
    XCTAssertTrue(app.staticTexts["Static expected after this action"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["guide.progress"].label, portraitProgress)
    capture(app, "Reduce Motion landscape expected after")
    revealAndTap(app.buttons["guide.acknowledge"], in: app)
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label != %@", portraitProgress),
      object: app.staticTexts["guide.progress"])], timeout: 10), .completed)
    XCUIDevice.shared.orientation = .portrait
    tap(app.buttons["practice.exit"])
  }

  @MainActor
  @discardableResult
  private func setReduceMotion(_ enabled: Bool, settings: XCUIApplication) throws -> Bool {
    settings.activate()
    let toggle = settings.switches["Reduce Motion"]
    if !toggle.waitForExistence(timeout: 2) {
      for _ in 0..<6 {
        if settings.navigationBars["Settings"].exists { break }
        let back = settings.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
      }
      let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
      for _ in 0..<8 {
        if accessibility.exists && accessibility.isHittable { break }
        settings.swipeUp()
      }
      tap(accessibility)
      let motion = settings.cells.containing(.staticText, identifier: "Motion").firstMatch
      for _ in 0..<8 {
        if motion.exists && motion.isHittable { break }
        settings.swipeUp()
      }
      tap(motion)
    }
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), settings.debugDescription)
    let original = toggle.value as? String == "1"
    let expected = enabled ? "1" : "0"
    if toggle.value as? String != expected {
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    let value = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [value], timeout: 5), .completed)
    return original
  }

  @MainActor private func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<40 {
      if element.exists && element.isHittable { break }
      let scroll = app.scrollViews.firstMatch
      var viewport = scroll.frame.intersection(app.frame)
      // The ScrollView's accessibility frame includes the navigation bar.
      // On a short viewport, swipeDown starts on that bar and cannot scroll.
      for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
        let overlap = viewport.intersection(bar.frame)
        if !overlap.isNull && overlap.minY <= viewport.minY {
          viewport.origin.y = overlap.maxY
          viewport.size.height = scroll.frame.maxY - overlap.maxY
        }
      }
      XCTAssertGreaterThan(viewport.height, 44, "Guide needs a usable scrolling viewport")
      let upper = app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.2))
      let lower = app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.8))
      let above = element.exists && element.frame.midY < viewport.midY
      (above ? upper : lower).press(forDuration: 0.05, thenDragTo: above ? lower : upper,
        withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0.3)
    }
    tap(element)
  }

  @MainActor private func tap(_ element: XCUIElement) {
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    element.tap()
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screen.name = name + " full screen"
    screen.lifetime = .keepAlways
    add(screen)
  }
}
