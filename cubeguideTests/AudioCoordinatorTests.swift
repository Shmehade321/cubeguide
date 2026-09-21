import CubeCore
import Foundation
import Testing

@testable import CubeSession
@testable import cubeguide

@MainActor
private final class ControlledNarration: InstructionAudio {
  private(set) var phrases: [Phrase] = []
  private(set) var stops = 0
  var completion: (@MainActor @Sendable () -> Void)?
  func play(_ phrase: Phrase, enabled: Bool, finished: @escaping @MainActor @Sendable () -> Void) {
    if enabled { phrases.append(phrase) }
    completion = finished
    if !enabled { finish() }
  }
  func pause() {
    stops += 1
    completion = nil
  }
  func stop() {
    stops += 1
    completion = nil
  }
  func finish() {
    let callback = completion
    completion = nil
    callback?()
  }
}

@MainActor
private final class AudioFrames: PreviewFrameSource {
  var callbacks: [@MainActor () -> Void] = []
  var time: Duration = .zero
  func start(_ update: @escaping @MainActor () -> Void) { callbacks.append(update) }
  func stop() {}
}

@MainActor
@Test("R08/R17: every guide direction maps to its exact phrase identity and caption")
func guidePhraseMapping() {
  let turns: [(QuarterTurns, String)] = [
    (.clockwise, "N01"), (.counterclockwise, "N02"), (.half, "N03"),
  ]
  for (turns, id) in turns {
    #expect(PhraseCatalog.phrase(for: .turn(Move(face: .front, turns: turns))).id == id)
  }
  let regrips: [(Regrip, String)] = [
    (.yawLeft, "N04"), (.yawRight, "N05"), (.topToward, "N06"),
    (.bottomToward, "N07"), (.rollClockwise, "N08"), (.rollCounterclockwise, "N09"),
  ]
  for (operation, id) in regrips {
    #expect(PhraseCatalog.phrase(for: .regrip(operation)).id == id)
  }
  #expect(PhraseCatalog.all.count == 30)
  #expect(Set(PhraseCatalog.all.map(\.id)).count == 30)
  #expect(PhraseCatalog.all[27].caption == "All six scanned faces are solved.")
}

@MainActor
@Test("R17: bundled phrase manifest exactly covers narration and effect identities")
func bundledPhraseManifest() throws {
  struct Manifest: Decodable {
    struct Entry: Decodable {
      let id: String
      let file: String
      let caption: String?
    }
    let version: Int
    let phrases: [Entry]
    let effects: [Entry]
  }
  let url = try #require(Bundle.main.url(forResource: "phrases", withExtension: "json"))
  let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  #expect(manifest.version == 1)
  #expect(manifest.phrases.map(\.id) == PhraseCatalog.all.map(\.id))
  #expect(manifest.phrases.map(\.caption) == PhraseCatalog.all.map { Optional($0.caption) })
  #expect(manifest.phrases.allSatisfy { $0.file == "\($0.id).m4a" })
  #expect(manifest.effects.map(\.id) == ["E01", "E02", "E03"])
}

@MainActor
@Test("R08/R17: narration finishes before animation and stale narration cannot start playback")
func narrationSequencesAnimation() async throws {
  let narration = ControlledNarration()
  let frames = AudioFrames()
  let presentation = GuidePresentation(
    frames: frames, now: { frames.time }, narration: narration)
  let practice = try await PracticeSession.start(
    preferences: AppPreferences(), playback: presentation)
  defer { practice.close() }
  let controller = practice.controller
  presentation.bind(controller)
  controller.send(.validateDraft)
  controller.send(.consent(true))
  await controller.waitForEffects()
  try #require(presentation.prepare())
  controller.send(.confirmAlignment)
  #expect(controller.send(.play) == .accepted)
  #expect(narration.phrases.count == 1)
  #expect(frames.callbacks.isEmpty)

  controller.send(.pause)
  narration.finish()
  #expect(frames.callbacks.isEmpty)
  #expect(controller.send(.play) == .accepted)
  #expect(narration.phrases.count == 2)
  narration.finish()
  #expect(frames.callbacks.count == 1)
}
