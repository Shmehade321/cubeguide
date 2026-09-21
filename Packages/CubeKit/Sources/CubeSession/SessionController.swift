import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Observation

public protocol SessionStorage: Actor {
  func startManual(revision: UInt64, lease: StorageLease) async throws
  func restore() async throws -> SessionRestoration
  func currentLease() async -> StorageLease
  func save(_ request: GuideSaveRequest, palette: CenterPalette, lease: StorageLease) async throws
  func saveDraft(_ draft: ManualDraft, lease: StorageLease) async throws
  func saveScanDraft(_ scan: PendingScan, lease: StorageLease) async throws
  func discardDraft(revision: UInt64, lease: StorageLease) async throws -> StorageLease
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

public enum ManualFallbackStatus: Equatable, Sendable { case idle, saving, failed }

public enum DraftDiscardStatus: Equatable, Sendable { case idle, saving, failed }

public enum SessionLoadStatus: Equatable, Sendable { case idle, loading, ready, failed }

@MainActor @Observable
public final class SessionController {
  public private(set) var manualFallbackStatus: ManualFallbackStatus = .idle
  @ObservationIgnored private var manualFallbackDraft: ManualDraft?
  @discardableResult public func switchScanToManual(
    confirmedCenters: CenterPalette, confirmed: Bool
  ) -> EventDisposition {
    guard loadStatus == .ready, discardStatus == .idle, !isStartingScan,
      session.phase != .deleting, session.phase != .deletionError,
      let workflow = scanWorkflow
    else { return .rejected(.unavailableEvent) }
    if manualFallbackStatus == .saving { return .ignored }
    guard manualFallbackStatus == .idle,
      workflow.phase != .freezing, workflow.phase != .faceReview,
      let input = workflow.pendingSave?.scan ?? workflow.durable
    else {
      return .rejected(.unavailableEvent)
    }
    guard confirmed else { return .rejected(.confirmationRequired) }
    let (revision, overflow) = max(session.latestInputRevision, input.draft.revision)
      .addingReportingOverflow(1)
    guard !overflow else { return .rejected(.revisionExhausted) }
    do {
      manualFallbackDraft = try ManualDraft(
        manualFallbackFrom: input.draft,
        confirmedCenters: confirmedCenters, revision: revision)
    } catch let error as DraftError {
      return .rejected(.draft(error))
    } catch { return .rejected(.unavailableEvent) }
    beginManualFallback()
    return .accepted
  }
  @discardableResult public func retryManualFallback() -> EventDisposition {
    guard manualFallbackStatus == .failed, manualFallbackDraft != nil else {
      return .rejected(.unavailableEvent)
    }
    beginManualFallback()
    return .accepted
  }
  private func beginManualFallback() {
    guard let draft = manualFallbackDraft else { return }
    generation = UUID()
    let expectedGeneration = generation
    manualFallbackStatus = .saving
    lastError = nil
    solveTask?.cancel()
    playback?.stop()
    stopCamera(discard: true)
    enqueueStorage { [self] in
      guard generation == expectedGeneration else { return }
      do {
        let current = await storage.currentLease()
        guard generation == expectedGeneration else { return }
        try await storage.saveDraft(draft, lease: current)
        guard generation == expectedGeneration else { return }
        let restored = try await storage.restore()
        guard generation == expectedGeneration else { return }
        session = restored.session
        palette = restored.palette
        lease = restored.lease
        pendingScan = restored.pendingScan
        scanWorkflow = restored.pendingScan.map { ScanWorkflow(restoring: $0) }
        manualFallbackStatus = .idle
        manualFallbackDraft = nil
        lastError = nil
      } catch {
        guard generation == expectedGeneration else { return }
        lastError = error
        manualFallbackStatus = .failed
      }
    }
  }
  public private(set) var discardStatus: DraftDiscardStatus = .idle
  @ObservationIgnored private var discardRevision: UInt64?
  @discardableResult public func discardDraft(confirmed: Bool) -> EventDisposition {
    guard loadStatus == .ready, manualFallbackStatus == .idle, !isStartingScan,
      session.phase != .deleting,
      session.phase != .deletionError
    else { return .rejected(.unavailableEvent) }
    if discardStatus == .saving { return .ignored }
    guard discardStatus == .idle else { return .rejected(.unavailableEvent) }
    let inputPhases: Set<SessionPhase> = [
      .home, .editing, .invalid, .alreadySolved,
      .offer, .solving, .solveError, .savingDraft, .draftStorageError,
    ]
    guard
      scanWorkflow != nil
        || (inputPhases.contains(session.phase)
          && session.hasWork && session.guideProgress == nil)
    else { return .rejected(.unavailableEvent) }
    guard confirmed else { return .rejected(.confirmationRequired) }
    let latest = max(
      session.latestInputRevision,
      scanWorkflow?.pendingSave?.scan.draft.revision ?? 0,
      pendingScan?.draft.revision ?? 0)
    let (revision, overflow) = latest.addingReportingOverflow(1)
    guard !overflow else { return .rejected(.revisionExhausted) }
    discardRevision = revision
    beginDiscard()
    return .accepted
  }
  @discardableResult public func retryDraftDiscard() -> EventDisposition {
    guard discardStatus == .failed, discardRevision != nil else {
      return .rejected(.unavailableEvent)
    }
    beginDiscard()
    return .accepted
  }
  private func beginDiscard() {
    guard let revision = discardRevision else { return }
    generation = UUID()
    let expectedGeneration = generation
    discardStatus = .saving
    lastError = nil
    solveTask?.cancel()
    playback?.stop()
    stopCamera(discard: true)
    enqueueStorage { [self] in
      guard generation == expectedGeneration else { return }
      do {
        let current = await storage.currentLease()
        guard generation == expectedGeneration else { return }
        _ = try await storage.discardDraft(revision: revision, lease: current)
        guard generation == expectedGeneration else { return }
        let restored = try await storage.restore()
        guard generation == expectedGeneration else { return }
        session = restored.session
        palette = restored.palette
        lease = restored.lease
        pendingScan = restored.pendingScan
        scanWorkflow = restored.pendingScan.map { ScanWorkflow(restoring: $0) }
        discardStatus = .idle
        discardRevision = nil
        lastError = nil
      } catch {
        guard generation == expectedGeneration else { return }
        let current = await storage.currentLease()
        guard generation == expectedGeneration else { return }
        lease = current
        discardStatus = .failed
        lastError = error
      }
    }
  }
  public private(set) var session = Session()
  public private(set) var loadStatus: SessionLoadStatus = .idle
  public private(set) var lastError: (any Error)?
  public private(set) var palette: CenterPalette?
  public private(set) var pendingScan: PendingScan?
  public private(set) var scanWorkflow: ScanWorkflow?
  public private(set) var isStartingScan = false
  public private(set) var isCameraReady = false

  @ObservationIgnored private let storage: any SessionStorage
  @ObservationIgnored private let solver: any SessionSolving
  @ObservationIgnored private let playback: (any GuidePlayback)?
  @ObservationIgnored private let camera: (any ScanCamera)?
  @ObservationIgnored private var lease: StorageLease?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var storageTail: Task<Void, Never>?
  @ObservationIgnored private var effects: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var solveTask: Task<Void, Never>?
  @ObservationIgnored private var solveRevision: UInt64?
  @ObservationIgnored private var scanStart: UUID?
  @ObservationIgnored private var cameraRun: UUID?

  public init(
    storage: any SessionStorage, solver: any SessionSolving, playback: (any GuidePlayback)? = nil,
    camera: (any ScanCamera)? = nil
  ) {
    self.storage = storage
    self.solver = solver
    self.playback = playback
    self.camera = camera
  }

  @discardableResult public func startScan(purpose: ScanPurpose, replacing: Bool = false) async
    -> EventDisposition
  {
    guard loadStatus == .ready, discardStatus == .idle, manualFallbackStatus == .idle,
      scanWorkflow == nil, !isStartingScan,
      session.pendingSave == nil, session.pendingDraftSave == nil,
      session.pendingManualStart == nil, session.pendingDeletion == nil
    else {
      return .rejected(.unavailableEvent)
    }
    switch purpose {
    case .newCube:
      guard session.phase == .home else { return .rejected(.unavailableEvent) }
      if session.hasWork && !replacing { return .rejected(.replacementRequired) }
    case .recovery:
      guard session.phase == .recovery else { return .rejected(.unavailableEvent) }
    case .verification:
      guard session.phase == .expectedSolved || session.phase == .completed else {
        return .rejected(.unavailableEvent)
      }
    }
    guard camera != nil else {
      lastError = SessionControllerError.missingCamera
      return .rejected(.unavailableEvent)
    }
    let token = UUID()
    let expectedGeneration = generation
    scanStart = token
    isStartingScan = true
    lastError = nil
    defer {
      if scanStart == token {
        scanStart = nil
        isStartingScan = false
      }
    }
    do {
      let restored = try await storage.restore()
      guard scanStart == token, generation == expectedGeneration, !Task.isCancelled else {
        return .ignored
      }
      guard restored.pendingScan == nil else { throw SessionStoreError.conflictingRecords }
      if purpose == .verification, restored.session.guideProgress?.isComplete != true {
        throw SessionStoreError.conflictingRecords
      }
      if purpose == .newCube, restored.session.hasWork && !replacing {
        return .rejected(.replacementRequired)
      }
      let latest = max(
        session.latestInputRevision, restored.session.latestInputRevision,
        restored.retainedGuideID?.revision ?? 0)
      let (revision, overflow) = latest.addingReportingOverflow(1)
      guard !overflow else { return .rejected(.revisionExhausted) }
      let pending = try PendingScan(
        draft: ScanDraft(revision: revision), purpose: purpose,
        retainedGuide: restored.retainedGuideID)
      // Adopt the actual durable context, which may include a write whose callback failed.
      let workflow = try ScanWorkflow(starting: pending)
      session = restored.session
      palette = restored.palette
      lease = restored.lease
      pendingScan = nil
      scanWorkflow = workflow
      generation = UUID()
      scanStart = nil
      isStartingScan = false
      solveTask?.cancel()
      playback?.stop()
      stopCamera(discard: true)
      return sendScan(.begin) == .accepted ? .accepted : .rejected(.unavailableEvent)
    } catch {
      guard scanStart == token, generation == expectedGeneration else { return .ignored }
      lastError = error
      return .rejected(.unavailableEvent)
    }
  }
  @discardableResult public func sendScan(_ event: ScanEvent) -> ScanDisposition {
    guard loadStatus == .ready, discardStatus == .idle, manualFallbackStatus == .idle,
      !isStartingScan,
      let workflow = scanWorkflow,
      session.phase != .deleting, session.phase != .deletionError
    else {
      return .rejected(.unavailableEvent)
    }
    if case .capture = event, !isCameraReady { return .rejected(.unavailableEvent) }
    let transition = ScanReducer.reduce(workflow, event: event)
    guard transition.disposition == .accepted else { return transition.disposition }
    scanWorkflow = transition.workflow
    pendingScan = transition.workflow.durable
    if case .saved = event { lastError = nil }
    for command in transition.commands { executeScan(command) }
    return transition.disposition
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
      scanWorkflow = restored.pendingScan.map { ScanWorkflow(restoring: $0) }
      lease = restored.lease
      loadStatus = .ready
    } catch {
      guard generation == expectedGeneration, loadStatus == .loading else { return }
      lastError = error
      loadStatus = .failed
    }
  }

  public func pauseForAuxiliaryNavigation() {
    if isStartingScan {
      _ = send(.background)
    } else if scanWorkflow != nil {
      _ = sendScan(.interrupt(.auxiliaryNavigation))
    } else if session.preview == .playing {
      _ = send(.pause)
    }
  }

  @discardableResult public func send(_ event: SessionEvent) -> EventDisposition {
    if playback == nil {
      switch event {
      case .play, .replay:
        lastError = SessionControllerError.missingPlayback
        return .rejected(.unavailableEvent)
      default: break
      }
    }
    if loadStatus != .ready {
      guard case .deleteLocalData = event else { return .rejected(.unavailableEvent) }
    }
    if discardStatus != .idle || manualFallbackStatus != .idle {
      switch event {
      case .deleteLocalData, .retryDeletion, .deleted, .deletionFailed: break
      default: return .rejected(.unavailableEvent)
      }
    }
    if isStartingScan {
      switch event {
      case .background, .cancel:
        scanStart = nil
        isStartingScan = false
        return .accepted
      case .deleteLocalData: break
      default: return .rejected(.unavailableEvent)
      }
    }
    if scanWorkflow != nil {
      // Lifecycle/navigation events belong to the scan while it retains the old guide.
      switch event {
      case .background: return scanLifecycle(.interrupt(.background))
      case .cancel: return scanLifecycle(.cancel)
      case .resume: return scanLifecycle(.open)
      case .deleteLocalData, .retryDeletion, .deleted, .deletionFailed: break
      default: return .rejected(.unavailableEvent)
      }
    }
    let transition = SessionReducer.reduce(session, event: event)
    guard transition.disposition == .accepted else { return transition.disposition }
    session = transition.session
    if case .deleted = event {
      pendingScan = nil
      scanWorkflow = nil
    }
    if case .manualStarted = event { palette = nil }
    if let draft = session.draft { palette = draft.palette }
    if transition.commands.contains(where: {
      if case .deleteLocalData = $0 { return true }
      return false
    }) {
      discardStatus = .idle
      discardRevision = nil
      manualFallbackStatus = .idle
      manualFallbackDraft = nil
      // Invalidates restores and callbacks immediately, before asynchronous deletion starts.
      generation = UUID()
      scanStart = nil
      isStartingScan = false
      stopCamera(discard: true)
      loadStatus = .ready
    }
    for command in transition.commands { execute(command) }
    return transition.disposition
  }

  private func scanLifecycle(_ event: ScanEvent) -> EventDisposition {
    switch sendScan(event) {
    case .accepted: .accepted
    case .ignored: .ignored
    case .rejected: .rejected(.unavailableEvent)
    }
  }
  private func stopCamera(discard: Bool) {
    cameraRun = nil
    isCameraReady = false
    camera?.stop()
    if discard { camera?.discardFrame() }
  }
  private func executeScan(_ command: ScanCommand) {
    let expectedGeneration = generation
    switch command {
    case .save(let request):
      let retainedLease = lease
      enqueueStorage { [self] in
        guard generation == expectedGeneration else { return }
        do {
          guard let retainedLease else { throw SessionControllerError.storageNotLoaded }
          try await storage.saveScanDraft(request.scan, lease: retainedLease)
          guard generation == expectedGeneration else { return }
          sendScan(.saved(request.id))
        } catch {
          guard generation == expectedGeneration else { return }
          if sendScan(.saveFailed(request.id)) == .accepted { lastError = error }
        }
      }
    case .startCapture(let slot):
      guard let camera else {
        lastError = SessionControllerError.missingCamera
        sendScan(.interrupt(.cameraUnavailable))
        return
      }
      let run = UUID()
      cameraRun = run
      isCameraReady = false
      camera.start(slot: slot) { [weak self] event in
        guard let self, self.generation == expectedGeneration, self.cameraRun == run else { return }
        switch event {
        case .ready:
          if self.scanWorkflow?.phase == .scanning { self.isCameraReady = true }
        case .interrupted(let reason): self.sendScan(.interrupt(reason))
        }
      }
    case .freeze(let id, let slot):
      guard let camera, let run = cameraRun else {
        lastError = SessionControllerError.missingCamera
        sendScan(.captureFailed(id, .cameraUnavailable))
        return
      }
      camera.freeze(id: id, slot: slot) { [weak self] result in
        guard let self, self.generation == expectedGeneration, self.cameraRun == run else { return }
        switch result {
        case .captured(let face): self.sendScan(.captured(id, face))
        case .failed(let reason): self.sendScan(.captureFailed(id, reason))
        }
      }
    case .stopCapture: stopCamera(discard: false)
    case .discardFrame: camera?.discardFrame()
    }
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
      playback?.play(action, id: id, restart: restart) { [weak self] completed in
        guard let self, self.generation == expectedGeneration else { return }
        self.send(.previewFinished(completed))
      }
    case .pausePreview: playback?.pause()
    case .stopPreview: playback?.stop()
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
  case storageNotLoaded, missingPalette, missingCamera, missingPlayback
}
