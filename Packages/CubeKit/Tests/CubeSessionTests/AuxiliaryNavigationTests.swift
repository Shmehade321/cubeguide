import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@MainActor @Test("R15: Help preserves manual work and pauses preview without acknowledging a move")
func auxiliaryPreservesWork() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let draft = ManualDraft(palette: try archivePalette(), revision: 1)
  try await store.saveDraft(draft, lease: store.currentLease())
  let playback = RecordingPlayback()
  let controller = SessionController(storage: store, solver: SolverService(), playback: playback)
  await controller.load()
  let manual = controller.session
  controller.pauseForAuxiliaryNavigation()
  #expect(controller.session == manual)
  let request = try #require(try preparingSession().pendingSave)
  let guideDirectory = directory.appendingPathComponent("guide")
  let guideStore = SessionStore(directory: guideDirectory)
  try await guideStore.save(request, palette: archivePalette(), lease: guideStore.currentLease())
  let guide = SessionController(storage: guideStore, solver: SolverService(), playback: playback)
  await guide.load()
  try #require(guide.send(.compare(.before)) == .accepted)
  try #require(guide.send(.play) == .accepted)
  let before = guide.session.guideProgress
  let id = try #require(guide.session.playbackID)
  guide.pauseForAuxiliaryNavigation()
  #expect(guide.session.phase == .guide && guide.session.preview == .paused)
  #expect(guide.session.guideProgress == before && playback.pauses == 1)
  playback.completions[0](id)
  #expect(guide.session.preview == .paused && guide.session.guideProgress == before)
  guide.pauseForAuxiliaryNavigation()
  #expect(playback.pauses == 1)
  #expect(guide.send(.play) == .accepted)
  #expect(playback.played.last?.2 == false && guide.session.guideProgress == before)
}

@MainActor
@Test("R15: Help interrupts capture without losing accepted faces or accepting late frames")
func auxiliaryPausesCapture() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let scan = try pendingScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let camera = RecordingScanCamera()
  let controller = SessionController(storage: store, solver: SolverService(), camera: camera)
  await controller.load()
  try #require(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  try #require(controller.sendScan(.capture) == .accepted)
  controller.pauseForAuxiliaryNavigation()
  #expect(controller.scanWorkflow?.phase == .pausedCapture && !controller.isCameraReady)
  #expect(controller.pendingScan == scan && camera.stops > 0 && camera.discarded > 0)
  let base = try #require(scan.draft.faces[2])
  let metadata = try CaptureMetadata(
    width: base.metadata.width, height: base.metadata.height,
    sourceOrientation: base.metadata.sourceOrientation,
    sourceMirrored: base.metadata.sourceMirrored,
    corners: base.metadata.corners, pose: CubeOrientation(front: .right, top: .up),
    samplingVersion: base.metadata.samplingVersion)
  let lateFace = try ScanFace(slot: .right, measurements: base.measurements, metadata: metadata)
  camera.completions[0](.captured(lateFace))
  #expect(controller.scanWorkflow?.phase == .pausedCapture && controller.pendingScan == scan)
  camera.events[0](.ready)
  #expect(!controller.isCameraReady)
  #expect(controller.sendScan(.capture) == .rejected(.unavailableEvent))
}

@MainActor @Test("R15: Help during scan startup prevents a delayed camera start")
func auxiliaryDuringScanStartup() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let storage = ControlledStorage(real)
  let camera = RecordingScanCamera()
  let controller = SessionController(storage: storage, solver: SolverService(), camera: camera)
  await controller.load()
  let gate = ControllerGate()
  await storage.gateNextRestore(gate)
  let start = Task { await controller.startScan(purpose: .newCube) }
  await gate.waitUntilEntered()
  controller.pauseForAuxiliaryNavigation()
  await gate.release()
  #expect(await start.value == .ignored)
  await controller.waitForEffects()
  #expect(!controller.isStartingScan && camera.starts.isEmpty && controller.pendingScan == nil)
}

@MainActor
@Test("R15: Help during a scan save preserves the save but prevents capture after acknowledgement")
func auxiliaryDuringScanSave() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let gate = ControllerGate()
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(store, draftGate: gate), solver: SolverService(), camera: camera)
  await controller.load()
  try #require(await controller.startScan(purpose: .newCube) == .accepted)
  await gate.waitUntilEntered()
  controller.pauseForAuxiliaryNavigation()
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.scanWorkflow?.phase == .pausedCapture)
  #expect(controller.scanWorkflow?.pauseReason == .auxiliaryNavigation)
  #expect(camera.starts.isEmpty && !controller.isCameraReady)
  #expect(controller.pendingScan == (try await store.loadScanDraft()))
  #expect(controller.pendingScan != nil)
}

@MainActor @Test("R15: Help does not cancel an active real solve or discard its verified result")
func auxiliaryDuringSolve() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let palette = try archivePalette()
  var draft = ManualDraft(palette: palette)
  let faces = try Facelets(notation: literalRight)
  for face in Face.allCases {
    for row in 0..<3 {
      for column in 0..<3 where row != 1 || column != 1 {
        draft = try draft.setting(
          face: face, row: row, column: column,
          color: palette.colors[
            Int(faces.faces[Int(face.rawValue) * 9 + row * 3 + column].rawValue)])
      }
    }
  }
  try await store.saveDraft(draft, lease: store.currentLease())
  let gate = ControllerGate()
  let solver = HeldControllerSolver(gate)
  let controller = SessionController(storage: store, solver: solver)
  await controller.load()
  try #require(controller.send(.validateDraft) == .accepted)
  try #require(controller.send(.consent(true)) == .accepted)
  await gate.waitUntilEntered()
  let before = controller.session
  controller.pauseForAuxiliaryNavigation()
  #expect(controller.session == before)
  await gate.release()
  await controller.waitForEffects()
  #expect(!(await solver.sawCancellation))
  #expect(controller.session.phase == .guide && controller.session.plan?.original == faces)
}
