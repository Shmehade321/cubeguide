import XCTest

final class FoundationUITests: XCTestCase {
  @MainActor
  func testRepeatedManualPreviewHomePreservesDraft() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tapReady(app.buttons["editor.home"]) }
    if app.buttons["home.delete"].exists {
      tapReady(app.buttons["home.delete"])
      // iOS 26 exposes the alert action and its nested button with the same ID.
      tapReady(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
    }
    tapReady(app.buttons["home.enterColors"])
    for (face, color) in [("U", "Green"), ("R", "White"), ("F", "Orange"),
      ("D", "Blue"), ("L", "Yellow"), ("B", "Red")] {
      tapReady(app.buttons["center.\(face)"])
      tapReady(app.buttons[color])
    }
    tapReady(app.buttons["centers.confirm"])
    tapReady(app.buttons["cell.U.0.0"])
    tapReady(app.sheets.buttons.matching(identifier: "sticker.blue").firstMatch)
    for cycle in 1...20 {
      XCTContext.runActivity(named: "Preview teardown and Home cycle \(cycle)") { _ in
        tapReady(app.buttons["editor.preview3D"])
        XCTAssertTrue(app.staticTexts["7 entered stickers · 47 unknown"].waitForExistence(timeout: 5))
        tapReady(app.buttons["preview.done"])
        XCTAssertTrue(app.buttons["cell.U.0.0"].label.contains("Blue"))
        tapReady(app.buttons["editor.home"])
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        tapReady(app.buttons["home.resume"])
        XCTAssertTrue(app.buttons["cell.U.0.0"].label.contains("Blue"))
        XCTAssertTrue(app.staticTexts["47 stickers left"].exists)
      }
    }
  }

  @MainActor
  func testPracticeExampleAndExit() {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tapReady(app.buttons["editor.home"]) }
    let practice = app.buttons["home.practice"]
    XCTAssertTrue(practice.waitForExistence(timeout: 5))
    guard practice.exists else { return }
    tapReady(practice)
    XCTAssertTrue(app.staticTexts["practice.banner"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["0 stickers left"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Labeled practice example"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    tapReady(app.buttons["editor.validate"])
    XCTAssertTrue(app.buttons["solve.consent"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["practice.banner"].exists)
    tapReady(app.buttons["solve.consent"])
    XCTAssertTrue(app.staticTexts["solve.verified"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["practice.banner"].exists)
    tapReady(app.buttons["practice.exit"])
    XCTAssertTrue(practice.waitForExistence(timeout: 5))
    tapReady(practice)
    XCTAssertTrue(app.staticTexts["0 stickers left"].waitForExistence(timeout: 5))
    tapReady(app.buttons["practice.exit"])
  }

  @MainActor
  func testSettingsPersistAndDelete() {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { tapReady(app.buttons["editor.home"]) }
    let settings = app.buttons["home.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    guard settings.exists else { return }
    tapReady(settings)
    tapReady(app.buttons["settings.delete"])
    tapReady(app.alerts.buttons.matching(identifier: "settings.delete.confirm").firstMatch)
    tapReady(settings)
    let narration = app.switches["settings.narration"]
    XCTAssertEqual(narration.value as? String, "1")
    narration.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    let saved = NSPredicate(format: "value == %@ AND enabled == true", "0")
    expectation(for: saved, evaluatedWith: narration)
    waitForExpectations(timeout: 5)
    for (identifier, expected) in [("settings.effects", "1"), ("settings.haptics", "0"), ("settings.labels", "0")] {
      let control = app.switches[identifier]
      control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
      expectation(for: NSPredicate(format: "value == %@ AND enabled == true", expected), evaluatedWith: control)
      waitForExpectations(timeout: 5)
    }
    tapReady(app.buttons["settings.speed"])
    tapReady(app.buttons["Fast"])
    XCTAssertTrue(app.buttons["settings.speed"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Persisted Settings"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    tapReady(app.buttons["settings.done"])
    app.terminate()
    app.launch()
    tapReady(settings)
    XCTAssertEqual(narration.value as? String, "0")
    XCTAssertEqual(app.switches["settings.effects"].value as? String, "1")
    XCTAssertEqual(app.switches["settings.haptics"].value as? String, "0")
    XCTAssertEqual(app.switches["settings.labels"].value as? String, "0")
    XCTAssertTrue(app.buttons["settings.speed"].label.contains("Fast"))
    tapReady(app.buttons["settings.delete"])
    tapReady(app.alerts.buttons.matching(identifier: "settings.delete.confirm").firstMatch)
    tapReady(settings)
    XCTAssertEqual(narration.value as? String, "1")
    XCTAssertEqual(app.switches["settings.effects"].value as? String, "0")
    XCTAssertEqual(app.switches["settings.haptics"].value as? String, "1")
    XCTAssertEqual(app.switches["settings.labels"].value as? String, "1")
    XCTAssertTrue(app.buttons["settings.speed"].label.contains("Normal"))
    tapReady(app.buttons["settings.done"])
  }

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
      app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch.tap()
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
    app.sheets.buttons.matching(identifier: "sticker.blue").firstMatch.tap()
    let changed = NSPredicate(format: "label CONTAINS %@", "Blue")
    expectation(for: changed, evaluatedWith: sticker)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.staticTexts["47 stickers left"].exists)
    tapReady(app.buttons["navigation.help"])
    tapReady(app.buttons["help.topic.manual"])
    XCTAssertTrue(app.staticTexts["Match your physical cube"].waitForExistence(timeout: 5))
    tapReady(app.buttons["help.done"])
    XCTAssertTrue(sticker.label.contains("Blue"))
    app.buttons["rotate.U"].tap()
    let rotated = app.buttons["cell.U.0.2"]
    expectation(for: changed, evaluatedWith: rotated)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(sticker.label.contains("Empty"))
    rotated.tap()
    app.sheets.buttons.matching(identifier: "sticker.clear").firstMatch.tap()
    XCTAssertTrue(app.staticTexts["48 stickers left"].waitForExistence(timeout: 5))
    sticker.tap()
    app.sheets.buttons.matching(identifier: "sticker.blue").firstMatch.tap()
    expectation(for: changed, evaluatedWith: sticker)
    waitForExpectations(timeout: 5)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Manual editor"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    tapReady(app.buttons["editor.preview3D"])
    XCTAssertTrue(app.staticTexts["7 entered stickers · 47 unknown"].waitForExistence(timeout: 5))
    let preview = XCTAttachment(screenshot: app.screenshot())
    preview.name = "Incomplete real manual cube in 3D"
    preview.lifetime = .keepAlways
    add(preview)
    tapReady(app.buttons["preview.done"])
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    XCTAssertTrue(app.staticTexts["47 stickers left"].exists)
    app.buttons["editor.home"].tap()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
    tapReady(app.buttons["home.practice"])
    XCTAssertTrue(app.staticTexts["practice.banner"].waitForExistence(timeout: 5))
    tapReady(app.buttons["cell.U.0.0"])
    tapReady(app.sheets.buttons.matching(identifier: "sticker.clear").firstMatch)
    XCTAssertTrue(app.staticTexts["1 stickers left"].waitForExistence(timeout: 5))
    tapReady(app.buttons["practice.exit"])
    tapReady(app.buttons["home.resume"])
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    XCTAssertTrue(app.staticTexts["47 stickers left"].exists)
    app.buttons["editor.home"].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    app.buttons["editor.home"].tap()
    enter.tap()
    app.alerts.buttons.matching(identifier: "replacement.keep").firstMatch.tap()
    app.buttons["home.resume"].tap()
    XCTAssertTrue(sticker.waitForExistence(timeout: 5))
    XCTAssertTrue(sticker.label.contains("Blue"))
    app.buttons["editor.home"].tap()
    enter.tap()
    app.alerts.buttons.matching(identifier: "replacement.confirm").firstMatch.tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertFalse(confirm.isEnabled)
    app.buttons["editor.home"].tap()
    app.buttons["home.delete"].tap()
    app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch.tap()
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
      tapReady(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
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
          let choice = app.sheets.buttons.matching(identifier: "sticker.\(color.lowercased())").firstMatch
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
    tapReady(app.sheets.buttons.matching(identifier: "sticker.blue").firstMatch)
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
    tapReady(app.sheets.buttons.matching(identifier: "sticker.green").firstMatch)
    tapReady(app.buttons["face.done"])
    XCTAssertNotEqual(app.buttons["cell.U.0.1"].value as? String, "Review this sticker")
    validate.tap()
    XCTAssertTrue(app.staticTexts["Your entered colors are solved"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["solve.consent"].exists)
    let artwork = app.descendants(matching: .any)["completion.artwork"].firstMatch
    XCTAssertTrue(artwork.waitForExistence(timeout: 5))
    XCTAssertEqual(artwork.value as? String, "Front Orange, top Green, right White")
    let completion = XCTAttachment(screenshot: app.screenshot())
    completion.name = "Entered solved colors retain custom palette"
    completion.lifetime = .keepAlways
    add(completion)
    tapReady(app.buttons["completion.save"])
    XCTAssertTrue(app.buttons["completion.home"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["Your entered colors are solved"].waitForExistence(timeout: 5))
    XCTAssertTrue(artwork.waitForExistence(timeout: 5))
    XCTAssertEqual(artwork.value as? String, "Front Orange, top Green, right White")
    tapReady(app.buttons["completion.home"])
    tapReady(app.buttons["home.delete"])
    tapReady(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
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
      tapReady(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
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
          let choice = app.sheets.buttons.matching(identifier: "sticker.\(color.lowercased())").firstMatch
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
    tapReady(app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch)
  }

  @MainActor
  func testOfflineHelpFromHome() {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      tapReady(app.buttons["editor.home"])
    }
    tapReady(app.buttons["home.help"])
    for (topic, heading) in [
      ("privacy", "Your cube stays on this iPhone"),
      ("capture", "Keep the sticker arrangement unchanged"),
      ("supported", "Standard six-color 3×3 cubes"),
      ("turns", "Face turns and whole-cube turns"), ("licenses", "Included components"),
      ("about", "About CubeGuide"),
    ] {
      tapReady(app.buttons["help.topic.\(topic)"])
      XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5))
      if topic == "about" {
        let version = app.staticTexts.matching(
          NSPredicate(format: "label BEGINSWITH %@", "Version ")
        ).firstMatch
        XCTAssertTrue(version.exists)
        XCTAssertTrue(version.label.contains("Build"))
        XCTAssertFalse(version.label.contains("Unavailable"))
      }
      if topic == "privacy" {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Bundled offline privacy help"
        screenshot.lifetime = .keepAlways
        add(screenshot)
      }
      tapReady(app.buttons["help.done"])
      tapReady(app.buttons["home.help"])
    }
    tapReady(app.buttons["help.done"])
    XCTAssertTrue(app.buttons["home.enterColors"].waitForExistence(timeout: 5))
  }

  @MainActor
  private func tapReady(_ element: XCUIElement) {
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"),
      object: element)
    let result = XCTWaiter.wait(for: [ready], timeout: 5)
    if result != .completed {
      let app = XCUIApplication()
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Unavailable control screenshot"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Unavailable control accessibility hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertEqual(result, .completed, "Control must exist, be hittable and enabled: \(element)")
    guard result == .completed else { return }
    element.tap()
  }

}
