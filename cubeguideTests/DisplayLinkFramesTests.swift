import RealityKit
import CubeCore
import CubeSession
import Testing
import XCTest
@testable import cubeguide

extension PresentationTests {
@MainActor
struct DisplayLinkFramesTests {
  @Test("R08/V10: production display clock completes a real scene preview")
  func realPlayback() async throws {
    let draft = try PracticeExample.draft()
    let scene = CubeSceneModel(draft: draft)
    let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: .clockwise),
      at: .identity, state: draft.canonicalFacelets(), sessionRevision: 1, moveIndex: 0).last)
    let player = GuideScenePlayback(scene: scene, palette: draft.palette,
      preferences: { var settings = AppPreferences(); settings.speed = .fast; return settings })
    defer { player.stop() }
    let done = XCTestExpectation(description: "Real preview completion")
    let id = PlaybackID(action: action.id, sequence: 1)
    player.play(action, id: id, restart: true) { actual in
      #expect(actual == id)
      done.fulfill()
    }
    let result = await XCTWaiter.fulfillment(of: [done], timeout: 5)
    #expect(result == .completed)
    #expect(scene.root.children.count == 26)
  }

  @Test("R08/R18: production frame source delivers on the run loop and stops on request")
  func deliveryAndStop() async {
    let frames = DisplayLinkFrames()
    let delivered = XCTestExpectation(description: "Actual display frame")
    let unwanted = XCTestExpectation(description: "Frame after stop")
    unwanted.isInverted = true
    var received = false
    frames.start {
      if received { unwanted.fulfill(); return }
      received = true
      frames.stop()
      delivered.fulfill()
    }
    let result = await XCTWaiter.fulfillment(of: [delivered], timeout: 2)
    #expect(result == .completed)
    let stopped = await XCTWaiter.fulfillment(of: [unwanted], timeout: 0.1)
    #expect(stopped == .completed)
  }

  @Test("R08/R18: replacing display subscription cancels the previous callback and releases its owner")
  func replacementAndRelease() async {
    var frames: DisplayLinkFrames? = DisplayLinkFrames()
    weak var weakFrames = frames
    let obsolete = XCTestExpectation(description: "Obsolete frame callback")
    obsolete.isInverted = true
    let current = XCTestExpectation(description: "Replacement display frame")
    frames?.start { obsolete.fulfill() }
    frames?.start { [weak frames] in frames?.stop(); current.fulfill() }
    let result = await XCTWaiter.fulfillment(of: [current], timeout: 2)
    #expect(result == .completed)
    let replaced = await XCTWaiter.fulfillment(of: [obsolete], timeout: 0.1)
    #expect(replaced == .completed)
    frames?.start {}
    frames = nil
    #expect(weakFrames == nil)
  }
}
}
