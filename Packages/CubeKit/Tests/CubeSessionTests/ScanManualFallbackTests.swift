import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

@Test(
  "R03: manual fallback preserves explicit rotated overrides and never guesses colors from measurements"
)
func manualFallbackModel() throws {
  let scan = try pendingScan().draft
    .setting(face: .front, row: 0, column: 0, color: .blue)
    .setting(face: .front, row: 2, column: 1, color: .red)
    .rotating(.front, by: .clockwise)
  let palette = try archivePalette()
  let manual = try ManualDraft(manualFallbackFrom: scan, confirmedCenters: palette, revision: 20)
  #expect(manual.revision == 20 && manual.palette == palette)
  #expect(manual.cells[20] == .blue && manual.cells[21] == .red)
  #expect(manual.missingCount == 46)
  for face in Face.allCases {
    for cell in 0..<9 {
      let index = Int(face.rawValue) * 9 + cell
      if cell == 4 {
        #expect(manual.cells[index] == palette.colors[Int(face.rawValue)])
      } else if index != 20 && index != 21 {
        #expect(manual.cells[index] == nil)
      }
    }
  }
  #expect(throws: DraftError.incomplete) { try manual.canonicalFacelets() }
  #expect(try DraftArchive.decode(DraftArchive.encode(manual)) == manual)
  #expect(throws: DraftError.invalidRevision) {
    try ManualDraft(manualFallbackFrom: scan, confirmedCenters: palette, revision: scan.revision)
  }
  #expect(throws: DraftError.invalidRevision) {
    try ManualDraft(
      manualFallbackFrom: ScanDraft(revision: .max), confirmedCenters: palette, revision: 0)
  }
}

@MainActor
@Test(
  "R03/R18: manual fallback requires confirmation and saves before editing while preserving the retained guide"
)
func manualFallbackBarrier() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  try await real.save(guide, palette: archivePalette(), lease: real.currentLease())
  let scan = try pendingScan(purpose: .recovery, guide: guide.id)
  try await real.saveScanDraft(scan, lease: real.currentLease())
  let guideBytes = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate), solver: SolverService(),
    playback: RecordingPlayback())
  await controller.load()
  let centers = try archivePalette()
  #expect(
    controller.switchScanToManual(confirmedCenters: centers, confirmed: false)
      == .rejected(.confirmationRequired))
  try #require(
    controller.switchScanToManual(confirmedCenters: centers, confirmed: true) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.manualFallbackStatus == .saving)
  #expect(controller.scanWorkflow != nil && controller.session.draft == nil)
  #expect(controller.send(.validateDraft) == .rejected(.unavailableEvent))
  #expect(controller.sendScan(.resume(confirmedUnchanged: true)) == .rejected(.unavailableEvent))
  #expect(controller.discardDraft(confirmed: true) == .rejected(.unavailableEvent))
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .idle && controller.session.phase == .editing)
  #expect(controller.scanWorkflow == nil && controller.pendingScan == nil)
  #expect(controller.session.draft?.revision == 11 && controller.session.draft?.missingCount == 48)
  #expect(
    try await SessionStore(directory: directory).restore().session.draft == controller.session.draft
  )
  #expect(try Data(contentsOf: directory.appendingPathComponent("guide.json")) == guideBytes)
}

@MainActor
@Test(
  "R03/R18: failed manual fallback remains blocked until retry and never restores scan input after a committed write"
)
func manualFallbackFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  try await real.saveScanDraft(pendingScan(), lease: real.currentLease())
  let controller = SessionController(
    storage: ControlledStorage(real, failDraft: true), solver: SolverService(),
    playback: RecordingPlayback())
  await controller.load()
  #expect(
    controller.switchScanToManual(confirmedCenters: try archivePalette(), confirmed: true)
      == .accepted)
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .failed && controller.lastError != nil)
  #expect(controller.scanWorkflow != nil)
  #expect(try await real.restore().session.draft?.revision == 11)
  #expect(controller.send(.cancel) == .rejected(.unavailableEvent))
  #expect(controller.sendScan(.retrySave) == .rejected(.unavailableEvent))
  #expect(controller.retryManualFallback() == .accepted)
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .idle && controller.lastError == nil)
  #expect(controller.session.phase == .editing && controller.scanWorkflow == nil)
}

@MainActor
@Test("R03/R13: fallback preserves accepted pending corrections and rejects late camera callbacks")
func manualFallbackPendingScan() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let initial = try PendingScan(draft: ScanDraft(revision: 1), purpose: .newCube)
  try await real.saveScanDraft(initial, lease: real.currentLease())
  let gate = ControllerGate()
  let camera = RecordingScanCamera()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate), solver: SolverService(),
    playback: RecordingPlayback(), camera: camera)
  await controller.load()
  #expect(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  #expect(controller.sendScan(.capture) == .accepted)
  let late = try #require(camera.completions.last)
  let centers = try archivePalette()
  #expect(
    controller.switchScanToManual(confirmedCenters: centers, confirmed: true)
      == .rejected(.unavailableEvent))
  late(.captured(try #require(pendingScan().draft.faces[2])))
  #expect(
    controller.switchScanToManual(confirmedCenters: centers, confirmed: true)
      == .rejected(.unavailableEvent))
  #expect(controller.sendScan(.editReview(.sticker(row: 0, column: 0, color: .blue))) == .accepted)
  #expect(controller.sendScan(.accept) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.switchScanToManual(confirmedCenters: centers, confirmed: true) == .accepted)
  #expect(controller.manualFallbackStatus == .saving && !controller.isCameraReady)
  late(.failed(.captureFailed))
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing && controller.scanWorkflow == nil)
  #expect(controller.session.draft?.cells[18] == .blue)
  #expect(controller.session.draft?.revision == 3)
  #expect(camera.starts == [.front])
  late(.captured(try #require(pendingScan().draft.faces[2])))
  #expect(controller.session.draft?.cells[18] == .blue && controller.scanWorkflow == nil)
}

@MainActor
@Test("R18: deletion supersedes a pending fallback without resurrecting either input kind")
func manualFallbackDeletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  try await real.saveScanDraft(pendingScan(), lease: real.currentLease())
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate), solver: SolverService(),
    playback: RecordingPlayback())
  await controller.load()
  try #require(
    controller.switchScanToManual(confirmedCenters: try archivePalette(), confirmed: true)
      == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .idle && controller.session.phase == .home)
  #expect(controller.session.draft == nil && controller.pendingScan == nil)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

private enum FallbackWriteFailure: Error { case interrupted }
@Test("V11: scan-to-manual atomic replacement restores exactly one complete input kind")
func manualFallbackWriteBoundaries() async throws {
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = SessionStore(directory: directory)
    let scan = try pendingScan()
    try await real.saveScanDraft(scan, lease: real.currentLease())
    let manual = try ManualDraft(
      manualFallbackFrom: scan.draft, confirmedCenters: archivePalette(), revision: 11)
    let failing = SessionStore(directory: directory) {
      if $0 == boundary { throw FallbackWriteFailure.interrupted }
    }
    await #expect(throws: FallbackWriteFailure.self) {
      try await failing.saveDraft(manual, lease: failing.currentLease())
    }
    let restored = try await SessionStore(directory: directory).restore()
    #expect(restored.pendingScan == (boundary == .afterReplace ? nil : scan))
    #expect(restored.session.draft == (boundary == .afterReplace ? manual : nil))
    try await real.saveDraft(manual, lease: real.currentLease())
    #expect(try await real.restore().session.draft == manual)
  }
}

@MainActor
@Test("R03/R18: overflow and absent scans cannot start fallback, while deletion remains available")
func manualFallbackGuards() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback())
  let palette = try archivePalette()
  #expect(
    controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
      == .rejected(.unavailableEvent))
  await controller.load()
  #expect(
    controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
      == .rejected(.unavailableEvent))
  #expect(controller.retryManualFallback() == .rejected(.unavailableEvent))
  try await real.saveScanDraft(pendingScan(revision: .max), lease: real.currentLease())
  let restored = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback())
  await restored.load()
  #expect(
    restored.switchScanToManual(confirmedCenters: palette, confirmed: true)
      == .rejected(.revisionExhausted))
  #expect(restored.send(.deleteLocalData(confirmed: true)) == .accepted)
  await restored.waitForEffects()
  #expect(try await real.loadScanDraft() == nil)
}

@MainActor
@Test(
  "R03/R10: verification scan fallback requires manual validation and can only claim entered-color completion"
)
func manualFallbackCompletionOrigin() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let guide = try #require(try savingCompletionSession().pendingSave)
  let palette = try archivePalette()
  try await real.save(guide, palette: palette, lease: real.currentLease())
  let base = try #require(pendingScan().draft.faces[2])
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  var scan = ScanDraft(revision: 10)
  for slot in ScanDraft.captureOrder {
    let color = palette.colors[Int(slot.rawValue)]
    var overrides: [CubeColor?] = Array(repeating: color, count: 9)
    overrides[4] = nil
    let metadata = try CaptureMetadata(
      width: 1920, height: 1440, sourceOrientation: .up,
      sourceMirrored: false, corners: base.metadata.corners,
      pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]),
      samplingVersion: "manual-overrides-fixture")
    scan = try scan.accepting(
      ScanFace(
        slot: slot, measurements: base.measurements,
        metadata: metadata, centerName: color, manualOverrides: overrides))
  }
  try await real.saveScanDraft(
    PendingScan(draft: scan, purpose: .verification, retainedGuide: guide.id),
    lease: real.currentLease())
  let controller = SessionController(
    storage: real, solver: SolverService(), playback: RecordingPlayback())
  await controller.load()
  #expect(controller.switchScanToManual(confirmedCenters: palette, confirmed: true) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .editing && controller.session.completion == nil)
  #expect(controller.send(.validateDraft) == .accepted)
  #expect(controller.session.phase == .alreadySolved)
  #expect(controller.send(.confirmCompletion) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.completion == .enteredColorsSolved)
  #expect(try await real.restore().session.completion == .enteredColorsSolved)
}
