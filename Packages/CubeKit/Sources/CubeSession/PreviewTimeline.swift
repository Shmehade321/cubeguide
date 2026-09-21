/// Presentation time only; does not own guide state or physical acknowledgement.
/// Timestamps are elapsed values from one monotonic clock origin chosen by the adapter.
public struct PreviewTimeline: Sendable {
  public private(set) var status: PreviewStatus = .idle
  private let rotationDuration: Duration
  private let beforeHold: Duration = .milliseconds(500)
  private var elapsed: Duration = .zero
  private var lastTime: Duration?

  public init(operation: GuideOperation, speed: GuideSpeed) {
    let normal: Int64
    if case .turn(let move) = operation, move.turns == .half { normal = 1800 }
    else { normal = 1200 }
    switch speed {
    case .slow: rotationDuration = .milliseconds(normal * 2)
    case .normal: rotationDuration = .milliseconds(normal)
    case .fast: rotationDuration = .milliseconds(normal / 2)
    }
  }

  public var progress: Double {
    if elapsed <= beforeHold { return 0 }
    if elapsed >= beforeHold + rotationDuration { return 1 }
    return seconds(elapsed - beforeHold) / seconds(rotationDuration)
  }

  /// Delay until the endpoint from the last sample; paused wall time is excluded.
  public var remainingDuration: Duration { beforeHold + rotationDuration - elapsed }

  public mutating func play(at time: Duration, restart: Bool = false) {
    if restart || status == .idle || status == .finished {
      elapsed = .zero
      lastTime = time
      status = .playing
    } else if status == .paused {
      lastTime = max(lastTime ?? time, time)
      status = .playing
    }
    // Duplicate Play while already playing must not reset the clock or progress.
  }

  public mutating func advance(to time: Duration) {
    guard status == .playing, let previous = lastTime, time >= previous else { return }
    elapsed = min(beforeHold + rotationDuration, elapsed + (time - previous))
    lastTime = time
    if elapsed == beforeHold + rotationDuration { status = .finished }
  }

  public mutating func pause(at time: Duration) {
    guard status == .playing else { return }
    advance(to: time)
    if status == .playing { status = .paused }
  }

  public mutating func stop() {
    status = .idle
    elapsed = .zero
    lastTime = nil
  }

  private func seconds(_ value: Duration) -> Double {
    let parts = value.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}
