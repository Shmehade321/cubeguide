import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

func pendingScan(
  revision: UInt64 = 10, purpose: ScanPurpose = .newCube,
  guide: SaveID? = nil
) throws -> PendingScan {
  let sample = try ColorMeasurement(
    median: LabColor(lightness: 50, a: 12, b: 30),
    display: DisplaySRGB(red: 0.5, green: 0.4, blue: 0.1), spread: 2, sampleCount: 1000)
  let metadata = try CaptureMetadata(
    width: 1920, height: 1440, sourceOrientation: .left,
    sourceMirrored: false,
    corners: [
      ImagePoint(x: 0.1, y: 0.1), ImagePoint(x: 0.9, y: 0.1),
      ImagePoint(x: 0.9, y: 0.9), ImagePoint(x: 0.1, y: 0.9),
    ],
    pose: .identity, samplingVersion: "store-fixture-v1")
  let face = try ScanFace(
    slot: .front, measurements: Array(repeating: sample, count: 9),
    metadata: metadata, centerName: .orange)
  return try PendingScan(
    draft: ScanDraft(revision: revision - 1).accepting(face),
    purpose: purpose, retainedGuide: guide)
}

@Test(
  "V11: scan archives are bounded, tagged and distinguish a pending observation from manual input")
func scanArchive() throws {
  let scan = try pendingScan()
  let bytes = try DraftArchive.encode(scan)
  #expect(try DraftArchive.decodeScan(bytes) == scan)
  #expect(throws: (any Error).self) { try DraftArchive.decode(bytes) }
  let manual = ManualDraft(palette: try archivePalette(), revision: 7)
  #expect(try DraftArchive.decode(DraftArchive.encode(manual)) == manual)
  #expect(throws: (any Error).self) { try DraftArchive.decodeScan(DraftArchive.encode(manual)) }
  #expect(throws: ArchiveError.unsupportedVersion) {
    try DraftArchive.decodeScan(mutatedArchive(bytes, envelope: { $0["schema"] = 2 }))
  }
  #expect(throws: ArchiveError.corrupt) {
    try DraftArchive.decodeScan(mutatedArchive(bytes, envelope: { $0["checksum"] = "bad" }))
  }
  #expect(throws: ArchiveError.sizeLimit) {
    try DraftArchive.decodeScan(Data(repeating: 32, count: DraftArchive.maximumBytes + 1))
  }
  #expect(throws: (any Error).self) {
    try DraftArchive.decodeScan(mutatedArchive(bytes, payload: { $0["kind"] = "unknown" }))
  }
  let invalid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scan)) as? [String: Any]
  var badContext = try #require(invalid)
  badContext["purpose"] = "verification"
  #expect(throws: (any Error).self) {
    try DraftArchive.decodeScan(mutatedArchive(bytes, payload: { $0["scan"] = badContext }))
  }
}

@Test("R10: recovery and verification drafts require a strictly older identified guide")
func pendingScanContextGuards() throws {
  for purpose in [ScanPurpose.recovery, .verification] {
    #expect(throws: ArchiveError.invalidProgress) {
      try PendingScan(draft: ScanDraft(revision: 4), purpose: purpose)
    }
  }
  for id in [
    SaveID(revision: 3, sequence: 0), SaveID(revision: 4, sequence: 1),
    SaveID(revision: .max, sequence: 1),
  ] {
    #expect(throws: ArchiveError.invalidProgress) {
      try PendingScan(draft: ScanDraft(revision: 4), purpose: .recovery, retainedGuide: id)
    }
  }
}

@Test("R10/R18: a partial verification scan survives relaunch without retiring the confirmed guide")
func scanStoreRetainsGuide() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try savingCompletionSession().pendingSave)
  try await store.save(guide, palette: archivePalette(), lease: store.currentLease())
  let original = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  let scan = try pendingScan(purpose: .verification, guide: guide.id)
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let restored = try await SessionStore(directory: directory).restore()
  #expect(restored.pendingScan == scan)
  #expect(restored.session.phase == .completed && restored.session.completion == .userConfirmed)
  #expect(!restored.session.aligned)
  #expect(restored.session.guideProgress == guide.progress)
  #expect(try Data(contentsOf: directory.appendingPathComponent("guide.json")) == original)
  #expect(try await store.loadDraft() == nil)
  #expect(try await store.loadScanDraft() == scan)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == [
      "draft.json", "guide.json",
    ])
}

@Test(
  "V11: scans and manual input share one ordered draft record; stale cross-kind writes are rejected"
)
func scanStoreOrdering() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let manual = ManualDraft(palette: try archivePalette(), revision: 9)
  try await store.saveDraft(manual, lease: store.currentLease())
  let scan = try pendingScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  #expect(try await store.loadDraft() == nil)
  #expect(try await store.loadScanDraft() == scan)
  #expect(try await store.restore().pendingScan == scan)
  for draft in [manual, ManualDraft(palette: manual.palette, revision: 10)] {
    await #expect(throws: SessionStoreError.staleWrite) {
      try await store.saveDraft(draft, lease: store.currentLease())
    }
  }
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let conflicting = try PendingScan(draft: ScanDraft(revision: 10), purpose: .newCube)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.saveScanDraft(conflicting, lease: store.currentLease())
  }
  let newer = ManualDraft(palette: manual.palette, revision: 11)
  try await store.saveDraft(newer, lease: store.currentLease())
  #expect(try await store.loadScanDraft() == nil)
  #expect(try await store.loadDraft() == newer)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.saveScanDraft(scan, lease: store.currentLease())
  }
}

@Test("R10: pending scans cannot bind missing, different or unfinished verification guides")
func scanStoreGuideBinding() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  let recovery = try pendingScan(purpose: .recovery, guide: guide.id)
  await #expect(throws: SessionStoreError.conflictingRecords) {
    try await store.saveScanDraft(recovery, lease: store.currentLease())
  }
  try await store.save(guide, palette: archivePalette(), lease: store.currentLease())
  for scan in [
    try pendingScan(),
    try pendingScan(purpose: .verification, guide: guide.id),
    try pendingScan(
      purpose: .recovery,
      guide: SaveID(revision: guide.id.revision, sequence: guide.id.sequence + 1)),
  ] {
    await #expect(throws: SessionStoreError.conflictingRecords) {
      try await store.saveScanDraft(scan, lease: store.currentLease())
    }
  }
  try await store.saveScanDraft(recovery, lease: store.currentLease())
  var advanced = try durableGuide()
  advanced = apply(advanced, .acknowledge(try #require(advanced.pendingAction).id)).session
  let next = try #require(advanced.pendingSave)
  await #expect(throws: SessionStoreError.conflictingRecords) {
    try await store.save(next, palette: archivePalette(), lease: store.currentLease())
  }
  // Simulate inconsistent files from another writer; restoration cannot silently trust either.
  try GuideArchive.encode(next, palette: archivePalette()).write(
    to: directory.appendingPathComponent("guide.json"))
  await #expect(throws: SessionStoreError.conflictingRecords) { try await store.restore() }
}

private enum ScanWriteFailure: Error { case interrupted }

@Test("V11: interrupted scan writes retain the old or new complete draft and preserve the guide")
func scanStoreWriteBoundaries() async throws {
  let guide = try #require(try preparingSession().pendingSave)
  let original = try pendingScan(purpose: .recovery, guide: guide.id)
  let next = try PendingScan(
    draft: original.draft.setting(face: .front, row: 0, column: 0, color: .red),
    purpose: original.purpose, retainedGuide: guide.id)
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    try await store.save(guide, palette: archivePalette(), lease: store.currentLease())
    try await store.saveScanDraft(original, lease: store.currentLease())
    let interrupted = SessionStore(directory: directory) {
      if $0 == boundary { throw ScanWriteFailure.interrupted }
    }
    await #expect(throws: ScanWriteFailure.self) {
      try await interrupted.saveScanDraft(next, lease: interrupted.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    let restored = try await reopened.restore()
    #expect(restored.pendingScan == (boundary == .afterReplace ? next : original))
    #expect(restored.session.guideProgress == guide.progress)
    try await reopened.saveScanDraft(next, lease: reopened.currentLease())
    #expect(try await reopened.restore().pendingScan == next)
  }
}

@Test("R18: manual replacement retires pending scan data and rejects its late callbacks")
func scanManualBoundary() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let scan = try pendingScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.startManual(revision: scan.draft.revision, lease: store.currentLease())
  }
  try await store.startManual(revision: 11, lease: store.currentLease())
  let restored = try await store.restore()
  #expect(
    restored.pendingScan == nil && restored.session.phase == .editing
      && restored.session.revision == 11)
  await #expect(throws: SessionStoreError.staleWrite) {
    try await store.saveScanDraft(scan, lease: store.currentLease())
  }
}

@Test("R18: deletion removes scan records and temporaries and rejects the old producer lease")
func scanStoreDeletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let scan = try pendingScan()
  let lease = await store.currentLease()
  try await store.saveScanDraft(scan, lease: lease)
  try Data("incomplete".utf8).write(to: directory.appendingPathComponent("draft.pending"))
  _ = try await store.delete(lease: lease)
  #expect(try await store.loadScanDraft() == nil)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.saveScanDraft(scan, lease: lease)
  }
}

@Test("V11: corrupt or future scan records are retained and block both kinds of draft overwrite")
func scanStorePreservesUnknown() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let scan = try pendingScan()
  let bytes = try DraftArchive.encode(scan)
  for invalid in [Data("invalid".utf8), try mutatedArchive(bytes, envelope: { $0["schema"] = 2 })] {
    let path = directory.appendingPathComponent("draft.json")
    try invalid.write(to: path)
    await #expect(throws: (any Error).self) { try await store.restore() }
    await #expect(throws: SessionStoreError.existingArchiveNeedsReview) {
      try await store.saveScanDraft(scan, lease: store.currentLease())
    }
    await #expect(throws: SessionStoreError.existingArchiveNeedsReview) {
      try await store.saveDraft(
        ManualDraft(palette: archivePalette(), revision: 11), lease: store.currentLease())
    }
    #expect(try Data(contentsOf: path) == invalid)
  }
}

@Test("R10: only a newer confirmed guide retires a pending scan; equal revisions conflict")
func scanStoreConfirmedReplacement() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let original = try #require(try preparingSession().pendingSave)
  try await store.save(original, palette: archivePalette(), lease: store.currentLease())
  let scan = try pendingScan(purpose: .recovery, guide: original.id)
  try await store.saveScanDraft(scan, lease: store.currentLease())
  for revision: UInt64 in [10, 11] {
    let next = try GuideSaveRequest(
      id: SaveID(revision: revision, sequence: 1), kind: .preparation,
      progress: GuideProgress(plan: original.progress.plan, revision: revision),
      pendingPrepared: true)
    if revision == 10 {
      await #expect(throws: SessionStoreError.conflictingRecords) {
        try await store.save(next, palette: archivePalette(), lease: store.currentLease())
      }
    } else {
      try await store.save(next, palette: archivePalette(), lease: store.currentLease())
      let restored = try await store.restore()
      #expect(restored.pendingScan == nil && restored.session.guideProgress == next.progress)
      #expect(restored.session.phase == .resumeCheck && !restored.session.aligned)
    }
  }
}

@MainActor
@Test(
  "R10/R18: coordinator retains pending scan context and cannot resume old guidance while it is pending"
)
func scanControllerRestoration() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  try await store.save(guide, palette: archivePalette(), lease: store.currentLease())
  let scan = try pendingScan(purpose: .recovery, guide: guide.id)
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let playback = RecordingPlayback()
  let controller = SessionController(storage: store, solver: SolverService(), playback: playback)
  await controller.load()
  #expect(controller.loadStatus == .ready && controller.pendingScan == scan)
  #expect(controller.send(.compare(.before)) == .rejected(.unavailableEvent))
  #expect(controller.send(.startManual(replacing: true)) == .rejected(.unavailableEvent))
  #expect(controller.send(.play) == .rejected(.unavailableEvent))
  #expect(playback.played.isEmpty)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .home && controller.pendingScan == nil)
  #expect(try await store.loadScanDraft() == nil)
}
