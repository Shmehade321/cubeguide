import XCTest

final class ScanFlowUITests: XCTestCase {
  @MainActor
  func testScanIntroductionStartsOnlyAfterExplanationAndKeepsManualFallback() throws {
    let app = XCUIApplication()
    app.launch()
    if app.buttons["editor.home"].waitForExistence(timeout: 2) {
      app.buttons["editor.home"].tap()
    }
    if app.buttons["home.delete"].exists {
      app.buttons["home.delete"].tap()
      app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch.tap()
      XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
    }

    let scan = app.buttons["home.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 5))
    scan.tap()
    XCTAssertTrue(app.staticTexts["Scan your cube"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Show all six faces without turning any layer."].exists)
    XCTAssertTrue(app.descendants(matching: .any)["scan.intro.wholeCube"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["scan.intro.sixFaces"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["scan.intro.review"].exists)
    XCTAssertTrue(app.buttons["scan.start"].exists)
    XCTAssertTrue(app.buttons["scan.manualFallback"].exists)

    app.buttons["scan.manualFallback"].tap()
    XCTAssertTrue(app.staticTexts["Assign center colors"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Scan your cube"].exists)
  }
}
