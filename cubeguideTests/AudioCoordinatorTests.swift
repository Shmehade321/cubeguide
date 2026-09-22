import AVFAudio
import CubeCore
import CubeScan
import Foundation
import Testing

@testable import CubeSession
@testable import cubeguide

@MainActor
private final class ControlledNarration: InstructionAudio {
  private(set) var phrases: [Phrase] = []
  private(set) var stops = 0
  var completion: (@MainActor @Sendable () -> Void)?
  var interruption: (@MainActor @Sendable () -> Void)?
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
  func setInterruptionHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
    interruption = handler
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
    let composites: [String: [String]]
  }
  let url = try #require(Bundle.main.url(forResource: "phrases", withExtension: "json"))
  let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  #expect(manifest.version == 1)
  #expect(manifest.phrases.map(\.id) == PhraseCatalog.all.map(\.id))
  #expect(manifest.phrases.map(\.caption) == PhraseCatalog.all.map { Optional($0.caption) })
  #expect(manifest.phrases.allSatisfy { $0.file == "\($0.id).m4a" })
  #expect(manifest.effects.map(\.id) == ["E01", "E02", "E03"])
  #expect(
    manifest.composites["pose"]
      == ["N16", "{frontColor:N10-N15}", "N17", "{topColor:N10-N15}", "N18", "{rightColor:N10-N15}"])
}

@MainActor
@Test("R17: bundled effects are decodable mono 44.1 kHz assets within their duration limits")
func bundledEffectsAreProductionReady() throws {
  let limits = ["E01": 0.150, "E02": 0.250, "E03": 0.800]
  for (identifier, maximumDuration) in limits {
    let url = try #require(Bundle.main.url(forResource: identifier, withExtension: "m4a"))
    let file = try AVAudioFile(forReading: url)
    #expect(file.processingFormat.channelCount == 1)
    #expect(file.processingFormat.sampleRate == 44_100)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    #expect(duration > 0)
    #expect(duration <= maximumDuration)
  }
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
  #expect(narration.phrases.map(\.id) == ["N16"])
  #expect(frames.callbacks.isEmpty)

  controller.send(.pause)
  narration.finish()
  #expect(frames.callbacks.isEmpty)
  #expect(controller.send(.play) == .accepted)
  #expect(narration.phrases.map(\.id) == ["N16", "N16"])
  for _ in 0..<7 where frames.callbacks.isEmpty {
    narration.finish()
  }
  #expect(frames.callbacks.count == 1)
}

@Test("R08/R17: pose narration orders labels before their exact colors")
@MainActor
func posePhraseOrdering() {
  #expect(
    PhraseCatalog.pose(front: .green, top: .white, right: .red).map(\.id)
      == ["N16", "N15", "N17", "N10", "N18", "N12"])
}

@MainActor
@Test("R08/R17: an audio interruption pauses the reducer and animation together")
func narrationInterruptionPausesGuide() async throws {
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
  controller.send(.confirmAlignment)
  #expect(controller.send(.play) == .accepted)
  for _ in 0..<7 where controller.session.preview != .playing {
    narration.finish()
  }
  #expect(controller.session.preview == .playing)

  narration.interruption?()

  #expect(controller.session.preview == .paused)
  #expect(narration.stops >= 1)
}
