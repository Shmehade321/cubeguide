import XCTest

/// From iOS 26, SwiftUI bottom-bar buttons sit inside a full-screen toolbar container and XCTest
/// reports them as not hittable, although a finger (a coordinate tap) reaches them. Treat an
/// enabled, on-screen toolbar button as reachable and tap its center like a finger would.
extension XCUIElement {
  var isReachable: Bool {
    if isHittable { return true }
    guard exists, !frame.isEmpty else { return false }
    let app = XCUIApplication()
    let inToolbar = app.toolbars.descendants(matching: .any)
      .matching(identifier: identifier).firstMatch.exists
    return inToolbar && app.windows.firstMatch.frame.contains(frame)
  }

  var isReadyToTap: Bool { exists && isEnabled && isReachable }

  func tapReachable() {
    if isHittable { tap() } else { coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
  }
}

extension NSPredicate {
  static var readyToTap: NSPredicate {
    NSPredicate { object, _ in (object as? XCUIElement)?.isReadyToTap ?? false }
  }
}

extension XCUIApplication {
  /// Launches on an isolated store (never the owner's saved cube) and clears any leftover
  /// scan, guide or entry from earlier runs, ending on an empty Home.
  @MainActor static func launchIsolatedAndClean(environment: [String: String] = [:])
    -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchEnvironment["CUBEGUIDE_UI_TEST_STORE"] = "1"
    app.launchEnvironment.merge(environment) { $1 }
    app.launch()
    if app.buttons["scan.cancel"].waitForExistence(timeout: 2) { app.buttons["scan.cancel"].tap() }
    if app.buttons["scan.discard"].waitForExistence(timeout: 2) {
      app.buttons["scan.discard"].tap()
      app.alerts.buttons.matching(identifier: "scan.discard.confirm").firstMatch.tap()
    }
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tapReachable() }
    // Leaving a guide passes through the physical comparison screen first.
    if app.buttons["editor.home"].waitForExistence(timeout: 2) { app.buttons["editor.home"].tapReachable() }
    if app.buttons["home.delete"].waitForExistence(timeout: 2) {
      app.buttons["home.delete"].tap()
      app.alerts.buttons.matching(identifier: "delete.confirm").firstMatch.tap()
      _ = app.buttons["home.delete"].waitForNonExistence(timeout: 5)
    }
    return app
  }
}
