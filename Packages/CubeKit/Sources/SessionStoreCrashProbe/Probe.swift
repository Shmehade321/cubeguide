import CubeCore
import CubeSession
import CubeSolver3
import Darwin
import Foundation

private enum ProbeError: Error { case arguments, unexpectedState }

/// Host-only qualification executable. Never linked into an app product.
@main
struct SessionStoreCrashProbe {
  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else { throw ProbeError.arguments }
    let directory = URL(fileURLWithPath: args[1], isDirectory: true)
    let store = SessionStore(directory: directory)
    switch args[0] {
    case "seed":
      guard args.count == 2 || (args.count == 3 && args[2] == "turn") else {
        throw ProbeError.arguments
      }
      try await store.startManual(revision: 1, lease: store.currentLease())
      try await store.saveDraft(
        ManualDraft(palette: palette(), revision: 2), lease: store.currentLease())
      try await store.save(
        preparation(afterAcknowledgements: args.count == 3 ? 1 : 0), palette: palette(),
        lease: store.currentLease())
    case "inspect":
      guard args.count == 2 else { throw ProbeError.arguments }
      let restored = try await store.restore()
      let session = restored.session
      let snapshot = Snapshot(
        phase: session.phase.rawValue, revision: session.revision,
        hasWork: session.hasWork, hasPlan: session.plan != nil, aligned: session.aligned,
        acknowledged: session.guideProgress?.acknowledgedActions,
        draftRevision: session.draft?.revision,
        draftCells: session.draft?.cells.map { $0?.rawValue },
        storedGuideAcknowledged: try await store.load()?.progress.acknowledgedActions)
      let bytes = try JSONEncoder().encode(snapshot)
      try FileHandle.standardOutput.write(contentsOf: bytes + Data([10]))
    case "mutate":
      guard args.count == 4 else { throw ProbeError.arguments }
      let boundary = StoreBoundary(rawValue: args[3])
      guard args[3] == "none" || boundary != nil else { throw ProbeError.arguments }
      let interrupted = SessionStore(directory: directory) { reached in
        if reached == boundary {
          try FileHandle.standardOutput.write(
            contentsOf: Data("BOUNDARY \(reached.rawValue)\n".utf8))
          guard Darwin.raise(SIGSTOP) == 0 else { throw ProbeError.unexpectedState }
          // The parent must kill this stopped process. Continuing is never a successful write.
          throw ProbeError.unexpectedState
        }
      }
      switch args[2] {
      case "guide", "turn":
        var session = try preparingSession(afterAcknowledgements: args[2] == "turn" ? 1 : 0)
        guard let preparation = session.pendingSave else { throw ProbeError.unexpectedState }
        session = SessionReducer.reduce(session, event: .persisted(preparation.id)).session
        session = SessionReducer.reduce(session, event: .confirmAlignment).session
        guard let action = session.pendingAction else { throw ProbeError.unexpectedState }
        session = SessionReducer.reduce(session, event: .acknowledge(action.id)).session
        guard let acknowledgement = session.pendingSave else { throw ProbeError.unexpectedState }
        try await interrupted.save(
          acknowledgement, palette: palette(), lease: interrupted.currentLease())
      case "draft":
        let draft = try ManualDraft(palette: palette(), revision: 3)
          .setting(face: .front, row: 0, column: 0, color: .red)
        try await interrupted.saveDraft(draft, lease: interrupted.currentLease())
      case "manual":
        try await interrupted.startManual(revision: 4, lease: interrupted.currentLease())
      case "delete":
        _ = try await interrupted.delete(lease: interrupted.currentLease())
      default: throw ProbeError.arguments
      }
    default: throw ProbeError.arguments
    }
  }

  private struct Snapshot: Encodable {
    let phase: String
    let revision: UInt64
    let hasWork: Bool
    let hasPlan: Bool
    let aligned: Bool
    let acknowledged: Int?
    let draftRevision: UInt64?
    let draftCells: [String?]?
    let storedGuideAcknowledged: Int?
  }

  private static func palette() throws -> CenterPalette {
    try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  }
  private static func preparation(afterAcknowledgements count: Int) throws -> GuideSaveRequest {
    guard let save = try preparingSession(afterAcknowledgements: count).pendingSave else {
      throw ProbeError.unexpectedState
    }
    return save
  }
  private static func preparingSession(afterAcknowledgements count: Int) throws -> Session {
    let faces = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    var session = SessionReducer.reduce(Session(), event: .startManual(replacing: false)).session
    guard let start = session.pendingManualStart else { throw ProbeError.unexpectedState }
    session = SessionReducer.reduce(session, event: .manualStarted(start)).session
    session = SessionReducer.reduce(session, event: .validate(faces)).session
    session = SessionReducer.reduce(session, event: .consent(true)).session
    guard let cube = session.confirmedCube else { throw ProbeError.unexpectedState }
    let plan = try Replay.verify(
      [Move(face: .right, turns: .counterclockwise)], for: cube,
      resourceVersion: "crash-qualification-literal-R"
    ).get()
    let result = SolverResponse(
      revision: session.revision, outcome: .verified(plan), elapsed: .zero, visitedNodes: 0)
    session = SessionReducer.reduce(session, event: .solveResult(result)).session
    for _ in 0..<count {
      guard let prepared = session.pendingSave else { throw ProbeError.unexpectedState }
      session = SessionReducer.reduce(session, event: .persisted(prepared.id)).session
      session = SessionReducer.reduce(session, event: .confirmAlignment).session
      guard let action = session.pendingAction else { throw ProbeError.unexpectedState }
      session = SessionReducer.reduce(session, event: .acknowledge(action.id)).session
      guard let saved = session.pendingSave else { throw ProbeError.unexpectedState }
      session = SessionReducer.reduce(session, event: .persisted(saved.id)).session
    }
    guard session.pendingSave != nil else { throw ProbeError.unexpectedState }
    return session
  }
}
