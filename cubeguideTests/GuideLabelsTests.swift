@testable import CubeSession
import RealityKit
import Testing
import SwiftUI
import UIKit
@testable import cubeguide

@MainActor
private final class LabelFrames: PreviewFrameSource {
  var callback: (@MainActor () -> Void)?
  var time: Duration = .zero
  func start(_ update: @escaping @MainActor () -> Void) { callback = update }
  func stop() { callback = nil }
}

extension PresentationTests {
  @MainActor
  struct GuideLabelsTests {
    @Test("R12: hosted guide observes saved label preferences without resetting playback")
    func hostedPolicy() async throws {
      let frames = LabelFrames()
      let presentation = GuidePresentation(frames: frames, now: { frames.time })
      var preferences = AppPreferences()
      preferences.showColorLabels = false
      let practice = try await PracticeSession.start(preferences: preferences, playback: presentation)
      defer { practice.close() }
      let controller = practice.controller
      presentation.bind(controller)
      controller.send(.validateDraft)
      controller.send(.consent(true))
      await controller.waitForEffects()
      let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
      let previous = windowScene.windows.first { $0.isKeyWindow }
      let window = UIWindow(windowScene: windowScene)
      try #require(!UIAccessibility.shouldDifferentiateWithoutColor)
      let host = UIHostingController(rootView:
        GuideFlowView(controller: controller, presentation: presentation))
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer {
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
      }
      try #require(try await eventually { presentation.scene != nil })
      let scene = try #require(presentation.scene)
      try #require(try await eventually { scene.root.parent != nil })
      func labels() -> Int {
        scene.stickers.values.reduce(0) { total, sticker in
          total + sticker.children.filter { $0.name.hasPrefix("label.") }.count
        }
      }
      #expect(labels() == 0)
      controller.send(.confirmAlignment)
      controller.send(.play)
      frames.time = .milliseconds(1100)
      frames.callback?()
      let transforms = scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) }
      preferences.showColorLabels = true
      #expect(controller.savePreferences(preferences) == .accepted)
      await controller.waitForEffects()
      let shown = try await eventually { labels() == 54 }
      try #require(shown)
      #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == transforms)
      #expect(controller.session.preview == .playing)
      #expect(controller.preferences.showColorLabels)
      preferences.showColorLabels = false
      #expect(controller.savePreferences(preferences) == .accepted)
      await controller.waitForEffects()
      try #require(try await eventually { labels() == 0 })
      controller.pauseForAuxiliaryNavigation()
      preferences.showColorLabels = true
      #expect(controller.savePreferences(preferences) == .accepted)
      await controller.waitForEffects()
      let shownAfterPause = try await eventually { labels() == 54 }
      try #require(shownAfterPause)
      #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == transforms)
      #expect(controller.session.preview == .paused)
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
    }

    @Test("R12: live label policy preserves preview transforms and never changes preferences or progress")
    func livePolicy() async throws {
      let frames = LabelFrames()
      let presentation = GuidePresentation(frames: frames, now: { frames.time })
      var preferences = AppPreferences()
      preferences.showColorLabels = false
      let practice = try await PracticeSession.start(preferences: preferences, playback: presentation)
      defer { practice.close() }
      let controller = practice.controller
      presentation.bind(controller)
      #expect(controller.send(.validateDraft) == .accepted)
      #expect(controller.send(.consent(true)) == .accepted)
      await controller.waitForEffects()
      try #require(presentation.prepare())
      let scene = try #require(presentation.scene)
      func labels() -> Int {
        scene.stickers.values.reduce(0) { total, sticker in
          total + sticker.children.filter { $0.name.hasPrefix("label.") }.count
        }
      }
      #expect(labels() == 0)
      #expect(controller.send(.confirmAlignment) == .accepted)
      #expect(controller.send(.play) == .accepted)
      frames.time = .milliseconds(1100)
      try #require(frames.callback != nil)
      frames.callback?()
      let transforms = scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) }
      presentation.refreshLabels(differentiateWithoutColor: true)
      #expect(labels() == 54)
      #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == transforms)
      #expect(controller.session.preview == .playing)
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
      #expect(!controller.preferences.showColorLabels)
      frames.time = .seconds(10)
      frames.callback?()
      #expect(controller.session.preview == .finished)
      #expect(labels() == 54)
      #expect(controller.send(.replay) == .accepted)
      #expect(labels() == 54)
      controller.send(.background)
      presentation.showComparison(after: true)
      #expect(labels() == 54)
      let comparison = scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) }
      presentation.refreshLabels(differentiateWithoutColor: false)
      #expect(labels() == 0)
      #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == comparison)
      preferences.showColorLabels = true
      #expect(controller.savePreferences(preferences) == .accepted)
      await controller.waitForEffects()
      presentation.refreshLabels(differentiateWithoutColor: false)
      #expect(labels() == 54)
      #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == comparison)
      #expect(controller.session.guideProgress?.acknowledgedActions == 0)
    }
  }
}

@MainActor
private func eventually(_ predicate: () -> Bool) async throws -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(3)
  while !predicate(), clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
  return predicate()
}
