import CubeCore
import CubeSolver3
import Foundation
import Observation

public protocol SessionStorage: Actor {
  func startManual(revision: UInt64, lease: StorageLease) async throws
  func restore() async throws -> SessionRestoration
  func currentLease() async -> StorageLease
  func save(_ request: GuideSaveRequest, palette: CenterPalette, lease: StorageLease) async throws
  func saveDraft(_ draft: ManualDraft, lease: StorageLease) async throws
  func delete(lease: StorageLease) async throws -> StorageLease
}
extension SessionStore: SessionStorage {}

public protocol SessionSolving: Actor {
  func solve(_ cube: LegalCube, revision: UInt64, budget: SolveBudget) async -> SolverResponse
}
extension SolverService: SessionSolving {}

/// The renderer reports only preview completion, never a physical acknowledgement.
@MainActor
public protocol GuidePlayback: AnyObject {
  func play(
    _ action: GuideAction, id: PlaybackID, restart: Bool,
    finished: @escaping @MainActor @Sendable (PlaybackID) -> Void)
  func pause()
  func stop()
}

public enum SessionLoadStatus: Equatable, Sendable { case idle, loading, ready, failed }

@MainActor @Observable
public final class SessionController {
  public private(set) var session = Session()
  public private(set) var loadStatus: SessionLoadStatus = .idle
  public private(set) var lastError: (any Error)?
  public private(set) var palette: CenterPalette?
  public private(set) var pendingScan: PendingScan?

  @ObservationIgnored private let storage: any SessionStorage
  @ObservationIgnored private let solver: any SessionSolving
  @ObservationIgnored private let playback: any GuidePlayback
  @ObservationIgnored private var lease: StorageLease?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var storageTail: Task<Void, Never>?
  @ObservationIgnored private var effects: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var solveTask: Task<Void, Never>?
  @ObservationIgnored private var solveRevision: UInt64?

  public init(storage: any SessionStorage, solver: any SessionSolving, playback: any GuidePlayback)
  {
    self.storage = storage
    self.solver = solver
    self.playback = playback
  }

  /// Load once before accepting workflow input. Failed reads retain the files for retry or deletion.
  public func load() async {
    guard loadStatus == .idle || loadStatus == .failed else { return }
    loadStatus = .loading
    lastError = nil
    let expectedGeneration = generation
    do {
      let restored = try await storage.restore()
      guard generation == expectedGeneration, loadStatus == .loading else { return }
      session = restored.session
      palette = restored.palette
      pendingScan = restored.pendingScan
      lease = restored.lease
      loadStatus = .ready
    } catch {
      guard generation == expectedGeneration, loadStatus == .loading else { return }
      lastError = error
      loadStatus = .failed
    }
  }

  @discardableResult public func send(_ event: SessionEvent) -> EventDisposition {
    if loadStatus != .ready {
      guard case .deleteLocalData = event else { return .rejected(.unavailableEvent) }
    }
    if pendingScan != nil {
      // The capture workflow owns this draft. Do not resume or replace its retained guide
      // through the unrelated manual/guide reducer while scan input is outstanding.
      switch event {
      case .deleteLocalData, .retryDeletion, .deleted, .deletionFailed: break
      default: return .rejected(.unavailableEvent)
      }
    }
    let transition = SessionReducer.reduce(session, event: event)
    guard transition.disposition == .accepted else { return transition.disposition }
    session = transition.session
    if case .deleted = event { pendingScan = nil }
    if case .manualStarted = event { palette = nil }
    if let draft = session.draft { palette = draft.palette }
    if transition.commands.contains(where: {
      if case .deleteLocalData = $0 { return true }
      return false
    }) {
      // Invalidates restores and callbacks immediately, before asynchronous deletion starts.
      generation = UUID()
      loadStatus = .ready
    }
    for command in transition.commands { execute(command) }
    return transition.disposition
  }

  private func execute(_ command: SessionCommand) {
    let expectedGeneration = generation
    switch command {
    case .startManual(let id):
      let retainedLease = lease
      enqueueStorage { [self] in
        guard generation == expectedGeneration else { return }
        do {
          guard let retainedLease else { throw SessionControllerError.storageNotLoaded }
          try await storage.startManual(revision: id.revision, lease: retainedLease)
          guard generation == expectedGeneration else { return }
          receive(.manualStarted(id))
        } catch {
          guard generation == expectedGeneration else { return }
          receive(.manualStartFailed(id), error: error)
        }
      }
    case .solve(let cube, let revision, let budget):
      solveTask?.cancel()
      solveRevision = revision
      let id = UUID()
      let task = Task { [self] in
        defer { effects[id] = nil }
        let result = await solver.solve(cube, revision: revision, budget: budget)
        guard generation == expectedGeneration else { return }
        send(.solveResult(result))
      }
      effects[id] = task
      solveTask = task
    case .cancelSolve(let revision):
      if solveRevision == revision {
        // Cancels even before the actor receives solve; SolverService forwards this to its worker.
        solveTask?.cancel()
        solveTask = nil
        solveRevision = nil
      }
    case .saveDraft(let request):
      let retainedLease = lease
      enqueueStorage { [self] in
        guard generation == expectedGeneration else { return }
        do {
          guard let retainedLease else { throw SessionControllerError.storageNotLoaded }
          try await storage.saveDraft(request.draft, lease: retainedLease)
          guard generation == expectedGeneration else { return }
          receive(.draftPersisted(request.id))
        } catch {
          guard generation == expectedGeneration else { return }
          receive(.draftPersistFailed(request.id), error: error)
        }
      }
    case .saveGuide(let request):
      let retainedLease = lease
      let retainedPalette = palette
      enqueueStorage { [self] in
        guard generation == expectedGeneration else { return }
        do {
          guard let retainedLease else { throw SessionControllerError.storageNotLoaded }
          guard let retainedPalette else { throw SessionControllerError.missingPalette }
          try await storage.save(request, palette: retainedPalette, lease: retainedLease)
          guard generation == expectedGeneration else { return }
          receive(.persisted(request.id))
        } catch {
          guard generation == expectedGeneration else { return }
          receive(.persistFailed(request.id), error: error)
        }
      }
    case .deleteLocalData(let id):
      enqueueStorage { [self] in
        guard generation == expectedGeneration else { return }
        do {
          // A failed deletion rotates the lease too; retries must obtain the current generation.
          let current = await storage.currentLease()
          let replacement = try await storage.delete(lease: current)
          guard generation == expectedGeneration else { return }
          lease = replacement
          palette = nil
          lastError = nil
          send(.deleted(id))
        } catch {
          guard generation == expectedGeneration else { return }
          lease = await storage.currentLease()
          lastError = error
          send(.deletionFailed(id))
        }
      }
    case .playPreview(let action, let id, let restart):
      playback.play(action, id: id, restart: restart) { [weak self] completed in
        guard let self, self.generation == expectedGeneration else { return }
        self.send(.previewFinished(completed))
      }
    case .pausePreview: playback.pause()
    case .stopPreview: playback.stop()
    }
  }

  private func receive(_ event: SessionEvent, error: (any Error)? = nil) {
    if send(event) == .accepted { lastError = error }
  }

  private func enqueueStorage(_ operation: @escaping @MainActor () async -> Void) {
    let previous = storageTail
    let id = UUID()
    let task = Task { [self] in
      await previous?.value
      await operation()
      effects[id] = nil
    }
    effects[id] = task
    storageTail = task
  }

  // Deterministic test drain includes follow-up preparation writes emitted by acknowledgements.
  func waitForEffects() async {
    while let task = effects.values.first { await task.value }
  }
}

public enum SessionControllerError: Error, Equatable, Sendable {
  case storageNotLoaded, missingPalette
}
