import XCTest

final class PreviewUITests: XCTestCase {
  @MainActor
  func testEditableExamplePreviewPreservesUnknownStickerAndPoseIsOnlyViewing() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tap(app.buttons["editor.home"]) }
    tap(app.buttons["home.practice"])
    XCTAssertTrue(app.staticTexts["practice.banner"].waitForExistence(timeout: 5))
    tap(app.buttons["cell.U.0.0"])
    tap(app.buttons["sticker.clear"])
    XCTAssertTrue(app.staticTexts["1 stickers left"].waitForExistence(timeout: 5))
    tap(app.buttons["editor.preview3D"])
    XCTAssertTrue(app.descendants(matching: .any)["preview.cube"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["53 entered stickers · 1 unknown"].exists)
    XCTAssertTrue(app.staticTexts["practice.banner"].exists)
    let initialPose = app.staticTexts["preview.pose"].label
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Editable example with one unknown sticker in 3D"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.swipeUp()
    tap(app.buttons["preview.left"])
    XCTAssertNotEqual(app.staticTexts["preview.pose"].label, initialPose)
    tap(app.buttons["preview.top"])
    tap(app.buttons["preview.reset"])
    XCTAssertEqual(app.staticTexts["preview.pose"].label, initialPose)
    tap(app.buttons["preview.done"])
    XCTAssertTrue(app.staticTexts["1 stickers left"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["cell.U.0.0"].label.contains("Empty"))
    tap(app.buttons["practice.exit"])
    XCTAssertTrue(app.buttons["home.practice"].waitForExistence(timeout: 5))
  }

  @MainActor
  private func tap(_ element: XCUIElement) {
    let ready = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)], timeout: 5), .completed)
    element.tap()
  }
}
