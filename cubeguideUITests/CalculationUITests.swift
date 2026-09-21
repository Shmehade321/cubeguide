#if DEBUG && targetEnvironment(simulator)
import XCTest

/// Presentation/coordinator tests with explicitly injected timing/failure boundaries.
/// These do not qualify real solver deadlines, corruption handling, or physical cancellation.
final class CalculationUITests: XCTestCase {
  @MainActor
  func testCancelCalculationKeepsInputAndRejectsLateRealResult() {
    let app = launch("delayedRealResult")
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.buttons["solve.cancel"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Verified result held"].waitForExistence(timeout: 5))
    let elapsed = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "seconds elapsed")).firstMatch
    XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
    let initial = elapsed.label
    let advances = NSPredicate { _, _ in elapsed.exists && elapsed.label != initial }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advances, object: nil)], timeout: 4), .completed)
    tap(app.buttons["solve.cancel"])
    XCTAssertTrue(app.staticTexts["Cancelled verified result returned"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["solve.consent"].waitForExistence(timeout: 5))
    tap(app.buttons["validation.edit"])
    XCTAssertTrue(app.staticTexts["0 stickers left"].waitForExistence(timeout: 5))
    tap(app.buttons["editor.home"])
    tap(app.buttons["home.resume"])
    XCTAssertTrue(app.staticTexts["0 stickers left"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["solve.verified"].exists)
  }

  @MainActor
  func testTimeoutAllowsOneExtendedAttemptAndPreservesInput() {
    let app = launch("timeout")
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.staticTexts["Calculation timed out"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["solve.retryLonger"].exists)
    capture(app, name: "Standard calculation timeout")
    tap(app.buttons["solve.retryLonger"])
    XCTAssertTrue(app.staticTexts["Your colors are saved. Check your entries or return Home."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["solve.retryLonger"].exists)
    XCTAssertTrue(app.staticTexts["Calculation timed out"].exists)
    tap(app.buttons["validation.edit"])
    XCTAssertTrue(app.staticTexts["0 stickers left"].waitForExistence(timeout: 5))
    tap(app.buttons["editor.home"])
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["solve.verified"].exists)
  }

  @MainActor
  func testResourceFailureOffersLocalHelpAndPreservesInput() {
    let app = launch("resourceFailure")
    tap(app.buttons["solve.consent"])
    XCTAssertTrue(app.staticTexts["Couldn't prepare a solution"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["The bundled solver resources couldn't be read. Close and restart the app. No download is required."].exists)
    XCTAssertFalse(app.buttons["solve.retryLonger"].exists)
    capture(app, name: "Bundled resource failure")
    tap(app.buttons["navigation.help"])
    tap(app.buttons["help.topic.privacy"])
    tap(app.buttons["help.done"])
    XCTAssertTrue(app.staticTexts["Couldn't prepare a solution"].waitForExistence(timeout: 5))
    tap(app.buttons["validation.edit"])
    XCTAssertTrue(app.staticTexts["0 stickers left"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["solve.verified"].exists)
  }

  @MainActor
  private func launch(_ scenario: String) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["CUBEGUIDE_CALCULATION_UI_TEST"] = scenario
    app.launch()
    XCTAssertTrue(app.staticTexts["calculation.testHarness"].waitForExistence(timeout: 5))
    tap(app.buttons["editor.validate"])
    XCTAssertTrue(app.buttons["solve.consent"].waitForExistence(timeout: 5))
    return app
  }
  @MainActor
  private func tap(_ element: XCUIElement) {
    let ready = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)], timeout: 5), .completed)
    element.tap()
  }
  @MainActor
  private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
#endif
