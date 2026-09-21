import Foundation

/// Identifies one deletion attempt, independently of bounded save and input counters.
public struct DeletionID: Equatable, Hashable, Sendable {
  private let value: UUID
  public init() { value = UUID() }
}
