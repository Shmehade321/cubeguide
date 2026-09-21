import Foundation

public enum GuideSpeed: String, Codable, CaseIterable, Sendable {
  case slow, normal, fast
}

public struct AppPreferences: Codable, Equatable, Sendable {
  public var narration = true
  public var effects = false
  public var haptics = true
  public var speed: GuideSpeed = .normal
  public var showColorLabels = true
  public init() {}
  public func colorLabelsEnabled(differentiateWithoutColor: Bool) -> Bool { showColorLabels || differentiateWithoutColor }
}
