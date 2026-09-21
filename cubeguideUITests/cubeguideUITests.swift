import XCTest

final class FoundationUITests: XCTestCase {
  @MainActor
  func testAppLaunches() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertEqual(app.state, .runningForeground)
  }

  @MainActor
  func testManualCentersEditingAndRelaunch() throws {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tap() }
    if app.buttons["home.delete"].exists {
      app.buttons["home.delete"].tap()
      app.buttons["delete.confirm"].tap()
    }
    let enter = app.buttons["home.enterColors"]
    XCTAssertTrue(enter.waitForExistence(timeout: 5))
    guard enter.exists else { return }
    enter.tap()
    let confirm = app.buttons["centers.confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertFalse(confirm.isEnabled)
    let assignments = [
      ("U", "Green"), ("R", "White"), ("F", "Orange"),
      ("D", "Blue"), ("L", "Yellow"), ("B", "Red"),
    ]
    for (face, color) in assignments {
      app.buttons["center.\(face)"].tap()
      app.buttons[color].tap()
    }
    app.buttons["center.R"].tap()
    app.buttons["Green"].tap()
    XCTAssertFalse(confirm.isEnabled)
    app.buttons["center.R"].tap()
    app.buttons["White"].tap()
    XCTAssertTrue(confirm.isEnabled)
    confirm.tap()
    let sticker = app.buttons["cell.U.0.0"]
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Empty"))
    XCTAssertTrue(app.buttons["cell.U.1.1"].label.contains("Green"))
    let center = app.buttons["cell.U.1.1"]
    XCTAssertTrue(center.isEnabled)
    guard center.isEnabled else { return }
    center.tap()
    XCTAssertTrue(app.buttons["centers.confirm"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].firstMatch.tap()
    sticker.tap()
    app.buttons["sticker.blue"].tap()
    let changed = NSPredicate(format: "label CONTAINS %@", "Blue")
    expectation(for: changed, evaluatedWith: sticker)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.staticTexts["47 stickers left"].exists)
    app.buttons["rotate.U"].tap()
    let rotated = app.buttons["cell.U.0.2"]
    expectation(for: changed, evaluatedWith: rotated)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(sticker.label.contains("Empty"))
    rotated.tap()
    app.buttons["sticker.clear"].tap()
    XCTAssertTrue(app.staticTexts["48 stickers left"].waitForExistence(timeout: 5))
    sticker.tap()
    app.buttons["sticker.blue"].tap()
    expectation(for: changed, evaluatedWith: sticker)
    waitForExpectations(timeout: 5)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Manual editor"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["editor.home"].tap()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    app.buttons["editor.home"].tap()
    enter.tap()
    app.buttons["replacement.keep"].tap()
    app.buttons["home.resume"].tap()
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    app.buttons["editor.home"].tap()
    enter.tap()
    app.buttons["replacement.confirm"].tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertFalse(confirm.isEnabled)
    app.buttons["editor.home"].tap()
    app.buttons["home.delete"].tap()
    app.buttons["delete.confirm"].tap()
    XCTAssertTrue(enter.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["home.resume"].exists)
  }
}
