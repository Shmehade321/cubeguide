/// These describe the evidence available to the app, not a camera observation.
public enum CompletionKind: String, Codable, Sendable {
  case enteredColorsSolved, userConfirmed, scanVerified
}
