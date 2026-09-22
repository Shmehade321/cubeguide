@preconcurrency import AVFAudio
import CubeCore
import CubeScan
import CubeSession
import UIKit

struct Phrase: Codable, Equatable, Sendable {
  let id: String
  let caption: String
  var filename: String { "\(id).m4a" }
}

enum PhraseCatalog {
  static let all: [Phrase] = [
    Phrase(id: "N01", caption: "Turn the front face clockwise one quarter turn."),
    Phrase(id: "N02", caption: "Turn the front face counterclockwise one quarter turn."),
    Phrase(id: "N03", caption: "Turn the front face halfway around."),
    Phrase(id: "N04", caption: "Turn the whole cube to the left."),
    Phrase(id: "N05", caption: "Turn the whole cube to the right."),
    Phrase(id: "N06", caption: "Bring the top face toward you."),
    Phrase(id: "N07", caption: "Bring the bottom face toward you."),
    Phrase(id: "N08", caption: "Roll the whole cube clockwise."),
    Phrase(id: "N09", caption: "Roll the whole cube counterclockwise."),
    Phrase(id: "N10", caption: "White."), Phrase(id: "N11", caption: "Yellow."),
    Phrase(id: "N12", caption: "Red."), Phrase(id: "N13", caption: "Orange."),
    Phrase(id: "N14", caption: "Blue."), Phrase(id: "N15", caption: "Green."),
    Phrase(id: "N16", caption: "Front."), Phrase(id: "N17", caption: "Top."),
    Phrase(id: "N18", caption: "Right."),
    Phrase(id: "N19", caption: "Rotate the whole cube. Do not turn a layer while scanning."),
    Phrase(id: "N20", caption: "Fit the face inside the grid, then take a picture."),
    Phrase(id: "N21", caption: "Check every color. Tap a square to change it."),
    Phrase(id: "N22", caption: "The colors need another check. Review the highlighted squares."),
    Phrase(id: "N23", caption: "Would you like help solving this cube?"),
    Phrase(id: "N24", caption: "Match how you are holding the cube to the picture."),
    Phrase(id: "N25", caption: "Tap when you have finished this move."),
    Phrase(id: "N26", caption: "If your cube looks different, pause and scan it again."),
    Phrase(id: "N27", caption: "The guide is finished. Check that your cube is solved."),
    Phrase(id: "N28", caption: "All six scanned faces are solved."),
    Phrase(id: "N29", caption: "Solving is taking longer. You can try again."),
    Phrase(id: "N30", caption: "Your entered colors are solved."),
  ]

  static func phrase(for operation: GuideOperation) -> Phrase {
    let index: Int
    switch operation {
    case .turn(let move):
      switch move.turns {
      case .clockwise: index = 0
      case .counterclockwise: index = 1
      case .half: index = 2
      }
    case .regrip(let regrip):
      switch regrip {
      case .yawLeft: index = 3
      case .yawRight: index = 4
      case .topToward: index = 5
      case .bottomToward: index = 6
      case .rollClockwise: index = 7
      case .rollCounterclockwise: index = 8
      }
    }
    return all[index]
  }

  static func pose(front: CubeColor, top: CubeColor, right: CubeColor) -> [Phrase] {
    [all[15], color(front), all[16], color(top), all[17], color(right)]
  }

  private static func color(_ color: CubeColor) -> Phrase {
    switch color {
    case .white: all[9]
    case .yellow: all[10]
    case .red: all[11]
    case .orange: all[12]
    case .blue: all[13]
    case .green: all[14]
    }
  }
}

@MainActor
protocol InstructionAudio: AnyObject {
  func play(_ phrase: Phrase, enabled: Bool, finished: @escaping @MainActor @Sendable () -> Void)
  func pause()
  func stop()
  func setInterruptionHandler(_ handler: @escaping @MainActor @Sendable () -> Void)
}

extension InstructionAudio {
  func setInterruptionHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {}
}

@MainActor
final class AudioCoordinator: NSObject, InstructionAudio, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private var completion: (@MainActor @Sendable () -> Void)?
  private var interruptionHandler: (@MainActor @Sendable () -> Void)?
  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor in self?.handleInterruption() }
      })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] note in
        let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        Task { @MainActor in self?.handleInterruption() }
      })
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  func play(_ phrase: Phrase, enabled: Bool, finished: @escaping @MainActor @Sendable () -> Void) {
    stop()
    guard enabled, !UIAccessibility.isVoiceOverRunning,
      let url = Bundle.main.url(forResource: phrase.id, withExtension: "m4a")
    else {
      finished()
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .spokenAudio, options: [.mixWithOthers])
      try session.setActive(true)
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      player.prepareToPlay()
      self.player = player
      completion = finished
      if !player.play() { complete() }
    } catch {
      finished()
    }
  }

  func pause() {
    player?.stop()
    player = nil
    completion = nil
  }

  func stop() { pause() }

  func setInterruptionHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
    interruptionHandler = handler
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.complete() }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    Task { @MainActor in self.complete() }
  }

  private func complete() {
    player = nil
    let callback = completion
    completion = nil
    callback?()
  }

  private func handleInterruption() {
    pause()
    interruptionHandler?()
  }
}

@MainActor
enum HapticFeedback {
  static func light(enabled: Bool, effectsEnabled: Bool = false) {
    EffectAudio.shared.play("E01", enabled: effectsEnabled)
    guard enabled else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
  static func warning(enabled: Bool, effectsEnabled: Bool = false) {
    EffectAudio.shared.play("E02", enabled: effectsEnabled)
    guard enabled else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
  }
  static func success(enabled: Bool, effectsEnabled: Bool = false) {
    EffectAudio.shared.play("E03", enabled: effectsEnabled)
    guard enabled else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
}

@MainActor
private final class EffectAudio: NSObject, AVAudioPlayerDelegate {
  static let shared = EffectAudio()
  private var player: AVAudioPlayer?

  func play(_ identifier: String, enabled: Bool) {
    player?.stop()
    player = nil
    guard enabled, let url = Bundle.main.url(forResource: identifier, withExtension: "m4a")
    else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      player.prepareToPlay()
      self.player = player
      _ = player.play()
    } catch {
      player = nil
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.player = nil }
  }
}
