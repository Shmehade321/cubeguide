import XCTest

/// How long a UI test waits for a control to become tappable, or for a tap's result to appear.
/// A hosted CI simulator can take several seconds to answer one accessibility query (10 s was
/// observed), so this allows several queries. It only bounds waiting: a step continues as soon
/// as its condition holds, and none of these waits asserts how fast the app responds.
let uiReadinessTimeout: TimeInterval = 30

extension XCTestCase {
  /// Keeps the screen and accessibility hierarchy when a control never became ready, so the
  /// failure can be diagnosed from the result bundle.
  @MainActor func attachUnavailableControl(_ app: XCUIApplication) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Unavailable control screenshot"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "Unavailable control accessibility hierarchy"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
  }
}
