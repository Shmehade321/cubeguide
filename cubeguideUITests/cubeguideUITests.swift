import XCTest

final class FoundationUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        // Foundation only: product screen assertions are introduced with T06.
    }
}
