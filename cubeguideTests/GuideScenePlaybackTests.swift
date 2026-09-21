import CubeCore
import CubeSession
import RealityKit
import Testing
@testable import cubeguide

@MainActor
private final class TestPreviewFrames: PreviewFrameSource {
  var callbacks: [@MainActor () -> Void] = []
  var active = false
  func start(_ update: @escaping @MainActor () -> Void) { callbacks.append(update); active = true }
  func stop() { active = false }
}
@MainActor
private final class PreviewClock {
  var time: Duration = .zero
  var finished: [PlaybackID] = []
}

extension PresentationTests {
@MainActor
struct GuideScenePlaybackTests {
  @Test("R08/R09: playback drives real scene, preserves paused progress and completes only current identity once")
  func playbackLifecycle() throws {
    let draft = try PracticeExample.draft()
    let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: .clockwise),
      at: .identity, state: draft.canonicalFacelets(), sessionRevision: 1, moveIndex: 0).last)
    let scene = CubeSceneModel(draft: draft)
    let frames = TestPreviewFrames(), clock = PreviewClock()
    let player = GuideScenePlayback(scene: scene, palette: draft.palette,
      preferences: { AppPreferences() }, frames: frames, now: { clock.time })
    let first = PlaybackID(action: action.id, sequence: 1)
    player.play(action, id: first, restart: true) { clock.finished.append($0) }
    try #require(frames.callbacks.count == 1 && frames.active)
    clock.time = .milliseconds(1100)
    frames.callbacks[0]()
    let point = try #require(scene.bodies.first { $0.key.x == 1 && $0.key.y == 1 && $0.key.z == 1 }?.value)
    let halfway = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(0,0,1)).act(SIMD3(1,1,1))
    #expect(simd_length(point.position(relativeTo: scene.root) - halfway) < 0.00001)
    player.pause()
    #expect(!frames.active)
    clock.time = .seconds(100)
    frames.callbacks[0]()
    #expect(simd_length(point.position(relativeTo: scene.root) - halfway) < 0.00001)
    #expect(clock.finished.isEmpty)
    let resumed = PlaybackID(action: action.id, sequence: 2)
    player.play(action, id: resumed, restart: false) { clock.finished.append($0) }
    try #require(frames.callbacks.count == 2)
    clock.time = .milliseconds(100600)
    frames.callbacks[0]()
    #expect(clock.finished.isEmpty)
    frames.callbacks[1]()
    #expect(clock.finished == [resumed] && !frames.active)
    frames.callbacks[1]()
    #expect(clock.finished == [resumed])
    player.stop()
    #expect(scene.stickers[0]?.findEntity(named: "label.\(draft.cells[0]!.title.prefix(1))") != nil)
  }

  @Test("R08/R11: replay and stop invalidate old frames and completion delivery")
  func playbackReplayStop() throws {
    let draft = try PracticeExample.draft()
    let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: .half),
      at: .identity, state: draft.canonicalFacelets(), sessionRevision: 1, moveIndex: 0).last)
    let scene = CubeSceneModel(draft: draft)
    let frames = TestPreviewFrames(), clock = PreviewClock()
    let player = GuideScenePlayback(scene: scene, palette: draft.palette,
      preferences: { var p = AppPreferences(); p.speed = .fast; return p }, frames: frames, now: { clock.time })
    player.play(action, id: PlaybackID(action: action.id, sequence: 1), restart: true) { clock.finished.append($0) }
    try #require(frames.callbacks.count == 1)
    clock.time = .seconds(1)
    frames.callbacks[0]()
    let second = PlaybackID(action: action.id, sequence: 2)
    player.play(action, id: second, restart: true) { clock.finished.append($0) }
    try #require(frames.callbacks.count == 2)
    clock.time = .milliseconds(2399)
    frames.callbacks[0]()
    #expect(clock.finished.isEmpty)
    frames.callbacks[1]()
    #expect(clock.finished.isEmpty)
    clock.time = .milliseconds(2400)
    frames.callbacks[1]()
    #expect(clock.finished == [second])
    player.play(action, id: PlaybackID(action: action.id, sequence: 3), restart: true) { clock.finished.append($0) }
    try #require(frames.callbacks.count == 3)
    player.stop()
    clock.time = .seconds(100)
    frames.callbacks[2]()
    #expect(clock.finished == [second] && !frames.active)
    #expect(scene.root.children.count == 26)
  }
}
}
