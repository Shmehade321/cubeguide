import XCTest

/// A second guide in the same launch with different center colors must show its own cube.
final class GuideSceneUITests: XCTestCase {
  // Literal R-turn fixture in canonical URFDLB order.
  private let facelets = Array("UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")

  @MainActor
  func testSecondGuideWithNewCentersShowsNewCube() throws {
    continueAfterFailure = false
    let app = XCUIApplication.launchIsolatedAndClean()

    app.buttons["home.enterColors"].tap()
    let first = try guideCube(app, centers: [
      "U": "Green", "R": "White", "F": "Orange", "D": "Blue", "L": "Yellow", "B": "Red",
    ])
    app.buttons["editor.home"].tapReachable()
    XCTAssertTrue(app.buttons["home.enterColors"].waitForExistence(timeout: 5))
    app.buttons["home.enterColors"].tap()
    app.alerts.buttons.matching(identifier: "replacement.confirm").firstMatch.tap()
    let second = try guideCube(app, centers: [
      "U": "White", "R": "Red", "F": "Green", "D": "Yellow", "L": "Orange", "B": "Blue",
    ])
    XCTAssertGreaterThan(
      difference(first, second), 3, "Second guide still shows the first cube's colors")
    app.terminate()
    _ = XCUIApplication.launchIsolatedAndClean()
  }

  @MainActor
  private func guideCube(_ app: XCUIApplication, centers: [String: String]) throws -> UIImage {
    let order = ["U", "R", "F", "D", "L", "B"]
    for face in order {
      wait(app.buttons["center.\(face)"]).tap()
      app.buttons[centers[face]!].tap()
    }
    wait(app.buttons["centers.confirm"]).tap()
    for (faceIndex, face) in order.enumerated() {
      wait(app.buttons["editor.faceMenu"]).tap()
      wait(app.buttons["focus.\(face)"]).tap()
      for cell in 0..<9 where cell != 4 {
        let color = centers[String(facelets[faceIndex * 9 + cell])]!
        wait(app.buttons["cell.\(face).\(cell / 3).\(cell % 3)"]).tap()
        wait(app.sheets.buttons.matching(identifier: "sticker.\(color.lowercased())").firstMatch)
          .tap()
      }
      wait(app.buttons["face.done"]).tap()
    }
    wait(app.buttons["editor.validate"]).tapReachable()
    wait(app.buttons["solve.consent"]).tap()
    XCTAssertTrue(app.buttons["guide.align"].waitForExistence(timeout: 20))
    let cube = app.descendants(matching: .any)["guide.animatedCube"].firstMatch
    XCTAssertTrue(cube.waitForExistence(timeout: 10))
    sleep(2)
    let shot = cube.screenshot()
    let attachment = XCTAttachment(screenshot: shot)
    attachment.lifetime = .keepAlways
    add(attachment)
    return shot.image
  }

  @MainActor
  private func wait(_ element: XCUIElement) -> XCUIElement {
    XCTAssertTrue(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: .readyToTap, object: element)], timeout: 10)
        == .completed, "\(element) not ready")
    return element
  }

  /// Mean per-channel difference (0-255) of two images scaled to 24 x 24. Mostly background:
  /// identical cubes measure 0, different palettes about 9.
  private func difference(_ first: UIImage, _ second: UIImage) -> Double {
    func pixels(_ image: UIImage) -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: 24 * 24 * 4)
      let context = CGContext(
        data: &bytes, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      if let cgImage = image.cgImage {
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 24, height: 24))
      }
      return bytes
    }
    let a = pixels(first)
    let b = pixels(second)
    return zip(a, b).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(a.count)
  }
}
