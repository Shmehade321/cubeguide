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
  @MainActor
  func testManualValidationAndSolvedCompletion() throws {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      tapReady(app.buttons["editor.home"])
    }
    if app.buttons["home.delete"].exists {
      tapReady(app.buttons["home.delete"])
      tapReady(app.buttons["delete.confirm"])
      XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
      XCTAssertTrue(app.buttons["home.resume"].waitForNonExistence(timeout: 5))
    }
    tapReady(app.buttons["home.enterColors"])
    let assignments = [
      ("U", "Green"), ("R", "White"), ("F", "Orange"),
      ("D", "Blue"), ("L", "Yellow"), ("B", "Red"),
    ]
    for (face, color) in assignments {
      tapReady(app.buttons["center.\(face)"])
      app.buttons[color].tap()
    }
    tapReady(app.buttons["centers.confirm"])
    let validate = app.buttons["editor.validate"]
    XCTAssertTrue(validate.waitForExistence(timeout: 5))
    guard validate.exists else { return }
    XCTAssertFalse(validate.isEnabled)
    for (face, color) in assignments {
      tapReady(app.buttons["editor.faceMenu"])
      tapReady(app.buttons["focus.\(face)"])
      for row in 0..<3 {
        for column in 0..<3 where row != 1 || column != 1 {
          let cell = app.buttons["cell.\(face).\(row).\(column)"]
          let ready = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
          expectation(for: ready, evaluatedWith: cell)
          waitForExpectations(timeout: 5)
          cell.tap()
          let choice = app.buttons["sticker.\(color.lowercased())"]
          expectation(for: ready, evaluatedWith: choice)
          waitForExpectations(timeout: 5)
          choice.tap()
          expectation(
            for: NSPredicate(format: "label CONTAINS %@ AND enabled == true", color),
            evaluatedWith: cell)
          waitForExpectations(timeout: 5)
        }
      }
      tapReady(app.buttons["face.done"])
    }
    XCTAssertTrue(validate.isEnabled)
    // Deliberately make one wrong entry, then correct the actual stored draft.
    tapReady(app.buttons["editor.faceMenu"])
    tapReady(app.buttons["focus.U"])
    tapReady(app.buttons["cell.U.0.0"])
    tapReady(app.buttons["sticker.blue"])
    tapReady(app.buttons["face.done"])
    validate.tap()
    XCTAssertTrue(app.staticTexts["Check your entered colors"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Green appears 8 times; it needs 9 stickers."].exists)
    tapReady(app.buttons["validation.edit"])
    XCTAssertEqual(app.buttons["cell.U.0.1"].value as? String, "Review this sticker")
    XCTAssertNotEqual(app.buttons["cell.U.0.0"].value as? String, "Review this sticker")
    let review = XCTAttachment(screenshot: app.screenshot())
    review.name = "Related stickers for count correction"
    review.lifetime = .keepAlways
    add(review)
    tapReady(app.buttons["editor.faceMenu"])
    tapReady(app.buttons["focus.U"])
    tapReady(app.buttons["cell.U.0.0"])
    tapReady(app.buttons["sticker.green"])
    tapReady(app.buttons["face.done"])
    XCTAssertNotEqual(app.buttons["cell.U.0.1"].value as? String, "Review this sticker")
    validate.tap()
    XCTAssertTrue(app.staticTexts["Your entered colors are solved"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["solve.consent"].exists)
    tapReady(app.buttons["completion.save"])
    XCTAssertTrue(app.buttons["completion.home"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["Your entered colors are solved"].waitForExistence(timeout: 5))
    tapReady(app.buttons["completion.home"])
    tapReady(app.buttons["home.delete"])
    tapReady(app.buttons["delete.confirm"])
  }

  @MainActor
  func testManualScrambleConsentAndRealSolver() throws {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      tapReady(app.buttons["editor.home"])
    }
    if app.buttons["home.delete"].exists {
      tapReady(app.buttons["home.delete"])
      tapReady(app.buttons["delete.confirm"])
      XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
      XCTAssertTrue(app.buttons["home.resume"].waitForNonExistence(timeout: 5))
    }
    tapReady(app.buttons["home.enterColors"])
    let assignments = [
      ("U", "Green"), ("R", "White"), ("F", "Orange"),
      ("D", "Blue"), ("L", "Yellow"), ("B", "Red"),
    ]
    for (face, color) in assignments {
      tapReady(app.buttons["center.\(face)"])
      app.buttons[color].tap()
    }
    tapReady(app.buttons["centers.confirm"])
    let validate = app.buttons["editor.validate"]
    XCTAssertTrue(validate.waitForExistence(timeout: 5))
    guard validate.exists else { return }
    XCTAssertFalse(validate.isEnabled)
    // Independent literal R-turn fixture in canonical URFDLB order.
    let facelets = Array("UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    let names: [Character: String] = [
      "U": "Green", "R": "White", "F": "Orange", "D": "Blue", "L": "Yellow", "B": "Red",
    ]
    for (faceIndex, assignment) in assignments.enumerated() {
      let face = assignment.0
      tapReady(app.buttons["editor.faceMenu"])
      tapReady(app.buttons["focus.\(face)"])
      for row in 0..<3 {
        for column in 0..<3 where row != 1 || column != 1 {
          let color = names[facelets[faceIndex * 9 + row * 3 + column]]!
          let cell = app.buttons["cell.\(face).\(row).\(column)"]
          let ready = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
          expectation(for: ready, evaluatedWith: cell)
          waitForExpectations(timeout: 5)
          cell.tap()
          let choice = app.buttons["sticker.\(color.lowercased())"]
          expectation(for: ready, evaluatedWith: choice)
          waitForExpectations(timeout: 5)
          choice.tap()
          expectation(
            for: NSPredicate(format: "label CONTAINS %@ AND enabled == true", color),
            evaluatedWith: cell)
          waitForExpectations(timeout: 5)
        }
      }
      tapReady(app.buttons["face.done"])
    }
    tapReady(validate)
    XCTAssertTrue(app.buttons["solve.consent"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["solve.verified"].exists)
    tapReady(app.buttons["solve.decline"])
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
    tapReady(app.buttons["home.resume"])
    XCTAssertTrue(app.buttons["solve.consent"].waitForExistence(timeout: 5))
    tapReady(app.buttons["solve.consent"])
    XCTAssertTrue(app.staticTexts["solve.verified"].waitForExistence(timeout: 20))
    let count = Int(app.staticTexts["solve.moveCount"].label.split(separator: " ").first ?? "")
    XCTAssertTrue(count.map { (1...30).contains($0) } ?? false)
    let result = XCTAttachment(screenshot: app.screenshot())
    result.name = "Verified real solver result"
    result.lifetime = .keepAlways
    add(result)
    tapReady(app.buttons["editor.home"])
    XCTAssertTrue(app.buttons["home.delete"].waitForExistence(timeout: 5))
    tapReady(app.buttons["home.delete"])
    tapReady(app.buttons["delete.confirm"])
  }

  @MainActor
  private func tapReady(_ element: XCUIElement) {
    expectation(
      for: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"),
      evaluatedWith: element)
    waitForExpectations(timeout: 5)
    element.tap()
  }

}
