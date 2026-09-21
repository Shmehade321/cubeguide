import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@MainActor
final class RecordingScanCamera: ScanCamera {
  var autoReady = true
  var starts: [Face] = []
  var events: [@MainActor @Sendable (ScanCameraEvent) -> Void] = []
  var freezes: [(ScanOperationID, Face)] = []
  var completions: [@MainActor @Sendable (ScanCameraResult) -> Void] = []
  var stops = 0
  var discarded = 0
  func start(slot: Face, event: @escaping @MainActor @Sendable (ScanCameraEvent) -> Void) {
    starts.append(slot)
    events.append(event)
    if autoReady { event(.ready) }
  }
  func freeze(
    id: ScanOperationID, slot: Face,
    completion: @escaping @MainActor @Sendable (ScanCameraResult) -> Void
  ) {
    freezes.append((id, slot))
    completions.append(completion)
  }
  func stop() { stops += 1 }
  func discardFrame() { discarded += 1 }
}

private func cameraObservation(_ slot: Face) throws -> ScanFace {
  let base = try #require(pendingScan().draft.faces[2])
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  let colors: [CubeColor] = [.green, .white, .orange, .blue, .yellow, .red]
  let metadata = try CaptureMetadata(
    width: base.metadata.width, height: base.metadata.height,
    sourceOrientation: base.metadata.sourceOrientation,
    sourceMirrored: base.metadata.sourceMirrored,
    corners: base.metadata.corners,
    pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]),
    samplingVersion: base.metadata.samplingVersion)
  return try ScanFace(
    slot: slot, measurements: base.measurements, metadata: metadata,
    centerName: colors[Int(slot.rawValue)])
}

private actor ScanCountingSolver: SessionSolving {
  var calls = 0
  func solve(_ cube: LegalCube, revision: UInt64, budget: SolveBudget) async -> SolverResponse {
    calls += 1
    return SolverResponse(revision: revision, outcome: .cancelled, elapsed: .zero, visitedNodes: 0)
  }
}

@MainActor
@Test(
  "R02/R18: scan startup saves its context before starting camera or accepting other workflow input"
)
func scanCoordinatorStartBarrier() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate),
    solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  #expect(await controller.startScan(purpose: .newCube) == .rejected(.unavailableEvent))
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.scanWorkflow?.phase == .saving && controller.pendingScan == nil)
  #expect(camera.starts.isEmpty && !controller.isCameraReady)
  #expect(controller.send(.startManual(replacing: true)) == .rejected(.unavailableEvent))
  #expect(controller.sendScan(.capture) == .rejected(.unavailableEvent))
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.scanWorkflow?.phase == .scanning && controller.isCameraReady)
  #expect(
    controller.pendingScan?.draft.revision == 1 && controller.pendingScan?.draft.acceptedCount == 0)
  #expect(camera.starts == [.front])
  #expect(try await real.loadScanDraft() == controller.pendingScan)
}

@MainActor
@Test(
  "R02/R05: six camera-adapter observations persist in order without solver consent or physical-completion claims"
)
func scanCoordinatorSixFaces() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let solver = ScanCountingSolver()
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: store, solver: solver, playback: RecordingPlayback(), camera: camera)
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  for (index, slot) in ScanDraft.captureOrder.enumerated() {
    try #require(controller.sendScan(.capture) == .accepted)
    #expect(camera.freezes.last?.1 == slot)
    let completion = try #require(camera.completions.last)
    completion(.captured(try cameraObservation(slot)))
    #expect(controller.scanWorkflow?.phase == .faceReview && !controller.isCameraReady)
    #expect(controller.pendingScan?.draft.acceptedCount == index)
    #expect(controller.sendScan(.accept) == .accepted)
    #expect(controller.scanWorkflow?.phase == .saving)
    await controller.waitForEffects()
    #expect(controller.pendingScan?.draft.acceptedCount == index + 1)
  }
  #expect(controller.scanWorkflow?.phase == .editing && !controller.isCameraReady)
  #expect(controller.session.completion == nil && controller.session.plan == nil)
  #expect(await solver.calls == 0)
  #expect(try await store.restore().pendingScan == controller.pendingScan)
  #expect(camera.starts == ScanDraft.captureOrder && camera.discarded >= 6)
}

@MainActor
@Test(
  "R02: camera readiness gates freeze and callbacks from old camera runs cannot interrupt or attach frames"
)
func scanCoordinatorCameraGenerations() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let scan = try pendingScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let camera = RecordingScanCamera()
  camera.autoReady = false
  let controller = SessionController(
    storage: store, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  #expect(controller.scanWorkflow?.phase == .pausedCapture && camera.starts.isEmpty)
  try #require(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  #expect(
    !controller.isCameraReady && controller.sendScan(.capture) == .rejected(.unavailableEvent))
  let oldEvent = try #require(camera.events.last)
  oldEvent(.ready)
  try #require(controller.sendScan(.capture) == .accepted)
  let oldFrame = try #require(camera.completions.last)
  #expect(controller.send(.background) == .accepted)
  #expect(controller.scanWorkflow?.phase == .pausedCapture && !controller.isCameraReady)
  #expect(
    controller.sendScan(.resume(confirmedUnchanged: false)) == .rejected(.confirmationRequired))
  camera.autoReady = true
  try #require(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  oldEvent(.interrupted(.permissionDenied))
  #expect(controller.scanWorkflow?.phase == .scanning && controller.isCameraReady)
  try #require(controller.sendScan(.capture) == .accepted)
  oldFrame(.captured(try cameraObservation(.right)))
  #expect(controller.scanWorkflow?.phase == .freezing && controller.scanWorkflow?.review == nil)
  let currentFrame = try #require(camera.completions.last)
  currentFrame(.captured(try cameraObservation(.right)))
  #expect(controller.scanWorkflow?.phase == .faceReview)
  #expect(controller.send(.cancel) == .accepted)
  #expect(controller.scanWorkflow?.phase == .home && controller.pendingScan == scan)
  #expect(controller.send(.resume) == .accepted && controller.scanWorkflow?.phase == .pausedCapture)
}

@MainActor
@Test(
  "R18: scan write failure after replacement requires retry and preserves interruption before camera start"
)
func scanCoordinatorSaveRetry() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(real, failDraft: true),
    solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  #expect(controller.scanWorkflow?.phase == .storageError && controller.lastError != nil)
  #expect(controller.pendingScan == nil && camera.starts.isEmpty)
  #expect(try await real.loadScanDraft() != nil)
  #expect(controller.send(.background) == .accepted)
  #expect(controller.sendScan(.retrySave) == .accepted)
  await controller.waitForEffects()
  #expect(controller.scanWorkflow?.phase == .pausedCapture && controller.lastError == nil)
  #expect(controller.pendingScan != nil && camera.starts.isEmpty)
  #expect(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  #expect(camera.starts == [.front] && controller.isCameraReady)
  try #require(controller.sendScan(.capture) == .accepted)
  let failure = try #require(camera.completions.last)
  failure(.failed(.cameraUnavailable))
  #expect(
    controller.scanWorkflow?.phase == .pausedCapture
      && controller.scanWorkflow?.pauseReason == .cameraUnavailable)
}

@MainActor
@Test(
  "R18: deletion waits for an in-flight scan save, stops camera and ignores its late acknowledgement"
)
func scanCoordinatorDeleteDuringSave() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let gate = ControllerGate()
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate),
    solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  #expect(controller.session.phase == .deleting && camera.stops > 0 && camera.discarded > 0)
  #expect(controller.sendScan(.retrySave) == .rejected(.unavailableEvent))
  await gate.release()
  await controller.waitForEffects()
  #expect(
    controller.session.phase == .home && controller.scanWorkflow == nil
      && controller.pendingScan == nil)
  #expect(camera.starts.isEmpty)
  #expect(try await real.loadScanDraft() == nil)
}

@MainActor
@Test(
  "R10: verification startup binds the latest durable guide rather than a stale loaded identity")
func scanCoordinatorFreshGuideIdentity() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let original = try #require(try savingCompletionSession().pendingSave)
  try await real.save(original, palette: archivePalette(), lease: real.currentLease())
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  let latest = GuideSaveRequest(
    id: SaveID(revision: original.id.revision, sequence: original.id.sequence + 1),
    kind: original.kind, progress: original.progress, pendingPrepared: original.pendingPrepared)
  try await real.save(latest, palette: archivePalette(), lease: real.currentLease())
  let bytes = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  try #require(await controller.startScan(purpose: .verification) == .accepted)
  await controller.waitForEffects()
  #expect(controller.pendingScan?.retainedGuide == latest.id)
  #expect(controller.pendingScan?.purpose == .verification)
  #expect(controller.session.completion == .userConfirmed)
  #expect(try Data(contentsOf: directory.appendingPathComponent("guide.json")) == bytes)
}

@MainActor
@Test("R10: verification cannot start when the fresh durable guide is no longer complete")
func scanCoordinatorFreshPurposeGuard() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let original = try #require(try savingCompletionSession().pendingSave)
  try await real.save(original, palette: archivePalette(), lease: real.currentLease())
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  let revision = original.id.revision + 1
  let next = try GuideSaveRequest(
    id: SaveID(revision: revision, sequence: 1), kind: .preparation,
    progress: GuideProgress(plan: original.progress.plan, revision: revision), pendingPrepared: true
  )
  try await real.save(next, palette: archivePalette(), lease: real.currentLease())
  #expect(await controller.startScan(purpose: .verification) == .rejected(.unavailableEvent))
  await controller.waitForEffects()
  #expect(controller.scanWorkflow == nil && controller.lastError != nil)
  #expect(camera.starts.isEmpty)
  #expect(try await real.loadScanDraft() == nil)
}

@MainActor
@Test(
  "R02/R18: new scan replacement requires consent; missing camera and exhausted revisions do not create drafts"
)
func scanCoordinatorStartGuards() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await controller.load()
  #expect(await controller.startScan(purpose: .verification) == .rejected(.unavailableEvent))
  #expect(await controller.startScan(purpose: .recovery) == .rejected(.unavailableEvent))
  #expect(controller.send(.startManual(replacing: false)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.send(.cancel) == .accepted)
  #expect(await controller.startScan(purpose: .newCube) == .rejected(.replacementRequired))
  try #require(await controller.startScan(purpose: .newCube, replacing: true) == .accepted)
  await controller.waitForEffects()
  #expect(controller.pendingScan?.draft.revision == 2)
  #expect(
    await controller.startScan(purpose: .newCube, replacing: true) == .rejected(.unavailableEvent))
  controller.send(.deleteLocalData(confirmed: true))
  await controller.waitForEffects()
  let absent = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback())
  await absent.load()
  #expect(await absent.startScan(purpose: .newCube) == .rejected(.unavailableEvent))
  #expect(absent.lastError != nil && absent.scanWorkflow == nil)
  #expect(try await real.loadScanDraft() == nil)
  try await real.saveDraft(
    ManualDraft(palette: archivePalette(), revision: .max), lease: real.currentLease())
  let exhausted = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
  await exhausted.load()
  exhausted.send(.cancel)
  #expect(
    await exhausted.startScan(purpose: .newCube, replacing: true) == .rejected(.revisionExhausted))
  #expect(exhausted.scanWorkflow == nil)
}

@MainActor
@Test("R18: cancellation or deletion during scan startup rejects the delayed store snapshot")
func scanCoordinatorDelayedStartup() async throws {
  for deleting in [false, true] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = SessionStore(directory: directory)
    let gate = ControllerGate()
    let camera = RecordingScanCamera()
    let storage = ControlledStorage(real)
    let controller = SessionController(
      storage: storage, solver: SolverService(), playback: RecordingPlayback(), camera: camera)
    await controller.load()
    await storage.gateNextRestore(gate)
    let start = Task { await controller.startScan(purpose: .newCube) }
    let deadline = ContinuousClock.now + .seconds(1)
    while !controller.isStartingScan, ContinuousClock.now < deadline { await Task.yield() }
    guard controller.isStartingScan else {
      await gate.release()
      _ = await start.value
      Issue.record("Startup did not enter the expected read barrier")
      continue
    }
    await gate.waitUntilEntered()
    #expect(controller.send(.startManual(replacing: false)) == .rejected(.unavailableEvent))
    #expect(
      controller.send(deleting ? .deleteLocalData(confirmed: true) : .background) == .accepted)
    await gate.release()
    #expect(await start.value == .ignored)
    await controller.waitForEffects()
    #expect(controller.scanWorkflow == nil && !controller.isStartingScan && camera.starts.isEmpty)
    #expect(try await real.loadScanDraft() == nil)
  }
}

@MainActor
@Test("R10: recovery capture retains its exact guide and blocks unrelated physical-guide commands")
func scanCoordinatorRecoveryContext() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let recovery = try #require(try savingRecoverySession().pendingSave)
  try await real.save(recovery, palette: archivePalette(), lease: real.currentLease())
  let bytes = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback(),
    camera: RecordingScanCamera())
  await controller.load()
  try #require(await controller.startScan(purpose: .recovery) == .accepted)
  await controller.waitForEffects()
  #expect(
    controller.pendingScan?.purpose == .recovery
      && controller.pendingScan?.retainedGuide == recovery.id)
  #expect(controller.session.recoveryRequired && !controller.session.aligned)
  #expect(controller.send(.compare(.before)) == .rejected(.unavailableEvent))
  #expect(try Data(contentsOf: directory.appendingPathComponent("guide.json")) == bytes)
}

@MainActor
@Test(
  "R18: deletion failure keeps scan context blocked; retry clears it and late frames cannot affect a new scan"
)
func scanCoordinatorDeleteRetryAndLateFrame() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(real, failDelete: true), solver: SolverService(),
    playback: RecordingPlayback(), camera: camera)
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  try #require(controller.sendScan(.capture) == .accepted)
  let old = try #require(camera.completions.last)
  controller.send(.deleteLocalData(confirmed: true))
  await controller.waitForEffects()
  #expect(controller.session.phase == .deletionError && controller.scanWorkflow != nil)
  #expect(
    !controller.isCameraReady && controller.sendScan(.capture) == .rejected(.unavailableEvent))
  #expect(controller.send(.retryDeletion) == .accepted)
  await controller.waitForEffects()
  #expect(controller.scanWorkflow == nil && controller.pendingScan == nil)
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await controller.waitForEffects()
  try #require(controller.sendScan(.capture) == .accepted)
  old(.captured(try cameraObservation(.front)))
  #expect(controller.scanWorkflow?.phase == .freezing && controller.scanWorkflow?.review == nil)
  let current = try #require(camera.completions.last)
  current(.captured(try cameraObservation(.front)))
  #expect(controller.scanWorkflow?.phase == .faceReview)
}
