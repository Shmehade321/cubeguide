import XCTest

/// Device-capable scan checks. They use an isolated store, so they never touch saved cubes.
final class ScanCameraUITests: XCTestCase {
  @MainActor private func launchClean() -> XCUIApplication { .launchIsolatedAndClean() }

  /// Cancel parks the scan on a resumable screen; discarding it returns Home.
  private func cancelScan(_ app: XCUIApplication) {
    app.buttons["scan.cancel"].tap()
    XCTAssertTrue(app.buttons["scan.resumeSaved"].waitForExistence(timeout: 5), "Cancel must leave the camera")
    XCTAssertFalse(app.staticTexts["Preparing camera…"].exists)
    discardParkedScan(app)
  }

  private func discardParkedScan(_ app: XCUIApplication) {
    app.buttons["scan.discard"].tap()
    app.alerts.buttons.matching(identifier: "scan.discard.confirm").firstMatch.tap()
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5), "Discard must return home")
  }

  private func shoot(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testCancelScanningReturnsHome() throws {
    let app = launchClean()
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))
    shoot(app, "01-home")
    app.buttons["home.scan"].tap()
    XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 5))
    app.buttons["scan.start"].tap()
    let cancel = app.buttons["scan.cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10))
    // Let the camera (or its unavailable/paused state) settle before cancelling.
    _ = app.buttons["scan.capture"].waitForExistence(timeout: 5)
    sleep(2)
    shoot(app, "02-scanning")
    cancelScan(app)
    shoot(app, "03-after-cancel")

    // A cancelled scan must not block starting another one.
    app.buttons["home.scan"].tap()
    XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 5))
    app.buttons["scan.start"].tap()
    XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 10))
    cancelScan(app)
  }

  /// Observation run for a real phone: records what the camera shows and whether a held face
  /// is captured automatically. Skipped where no camera is available.
  @MainActor
  func testLiveScanObservation() throws {
    let app = launchClean()
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))
    app.buttons["home.scan"].tap()
    app.buttons["scan.start"].tap()
    guard app.buttons["scan.capture"].waitForExistence(timeout: 10) else {
      throw XCTSkip("No camera on this destination")
    }
    let review = app.buttons["scan.acceptFace"]
    for second in stride(from: 2, through: 30, by: 2) {
      if review.waitForExistence(timeout: 2) { break }
      shoot(app, String(format: "live-%02d", second))
    }
    if review.exists {
      shoot(app, "review")
      app.swipeUp()
      shoot(app, "review-grid")
    }
    cancelScan(app)
  }

  /// Walks every route back to Home and records the title each time (large title regressions).
  @MainActor
  func testHomeTitleAfterEveryReturn() throws {
    let app = launchClean()
    let title = app.navigationBars.staticTexts["CubeGuide"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    shoot(app, "t1-home")

    app.buttons["home.scan"].tap()
    app.buttons["scan.cancelIntro"].tap()
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))
    sleep(1)
    shoot(app, "t2-after-intro-cancel")

    app.buttons["home.scan"].tap()
    app.buttons["scan.start"].tap()
    XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 10))
    sleep(2)
    shoot(app, "t3-scan")
    cancelScan(app)
    sleep(1)
    shoot(app, "t4-after-scan-cancel")

    app.buttons["home.enterColors"].tap()
    XCTAssertTrue(app.buttons["editor.home"].waitForExistence(timeout: 5))
    app.buttons["editor.home"].tap()
    XCTAssertTrue(app.buttons["home.scan"].waitForExistence(timeout: 5))
    sleep(1)
    shoot(app, "t5-after-manual-home")
    XCTAssertTrue(title.exists)
  }
}
