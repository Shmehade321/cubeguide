import CubeCore
@testable import CubeSession
import RealityKit
import Testing
@testable import cubeguide

@MainActor
private final class PresentationFrames: PreviewFrameSource {
  var callbacks: [@MainActor () -> Void] = []
  var time: Duration = .zero
  func start(_ update: @escaping @MainActor () -> Void) { callbacks.append(update) }
  func stop() {}
}

extension PresentationTests {
@MainActor
struct GuidePresentationTests {
  @Test("R09/R11: persistent presentation survives screen preparation and reports preview without acknowledgement")
  func controllerComposition() async throws {
    let frames = PresentationFrames()
    let presentation = GuidePresentation(frames: frames, now: { frames.time })
    let practice = try await PracticeSession.start(preferences: AppPreferences(), playback: presentation)
    defer { practice.close() }
    let controller = practice.controller
    presentation.bind(controller)
    #expect(controller.send(.validateDraft) == .accepted)
    #expect(controller.send(.consent(true)) == .accepted)
    await controller.waitForEffects()
    try #require(controller.session.phase == .guide && controller.session.preparationDurable)
    try #require(presentation.prepare())
    #expect(presentation.previewDescription == "Before this action")
    let scene = try #require(presentation.scene)
    let action = try #require(controller.session.guideProgress?.pending)
    #expect(controller.send(.confirmAlignment) == .accepted)
    #expect(controller.send(.play) == .accepted)
    try #require(frames.callbacks.count == 1)
    frames.time = .milliseconds(1100)
    frames.callbacks[0]()
    #expect(presentation.previewDescription == "Demonstration in progress")
    let transforms = scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) }
    #expect(presentation.prepare())
    #expect(presentation.scene === scene)
    #expect(scene.bodies.mapValues { $0.transformMatrix(relativeTo: scene.root) } == transforms)
    #expect(controller.send(.pause) == .accepted)
    #expect(presentation.previewDescription == "Paused demonstration")
    #expect(controller.send(.play) == .accepted)
    frames.time = .seconds(10)
    try #require(frames.callbacks.count == 2)
    frames.callbacks[1]()
    #expect(presentation.previewDescription == "Expected after this action")
    #expect(controller.session.preview == .finished)
    #expect(controller.session.guideProgress?.acknowledgedActions == 0)
    #expect(controller.send(.acknowledge(action.id)) == .accepted)
    await controller.waitForEffects()
    #expect(controller.session.guideProgress?.acknowledgedActions == 1)
    #expect(presentation.prepare())
    #expect(presentation.scene === scene)
    controller.send(.background)
    frames.callbacks[0]()
    #expect(controller.session.phase == .resumeCheck && !controller.session.aligned)
    #expect(controller.session.guideProgress?.acknowledgedActions == 1)
  }
}
}
