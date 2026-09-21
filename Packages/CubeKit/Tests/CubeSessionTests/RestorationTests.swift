import CubeCore
import Foundation
import Testing

@testable import CubeSession

@Test("V11: empty storage restores Home; a partial draft restores unconfirmed editing")
func restoreEmptyAndDraft() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let empty = try await store.restore()
  #expect(empty.session == Session())
  #expect(empty.palette == nil)
  let lease = await store.currentLease()
  #expect(empty.lease == lease)
  let draft = try ManualDraft(palette: archivePalette(), revision: 10)
    .setting(face: .right, row: 0, column: 0, color: .green)
  try await store.saveDraft(draft, lease: empty.lease)
  let result = try await store.restore()
  #expect(result.session.phase == .editing && result.session.hasWork)
  #expect(result.session.draft == draft && result.session.durableDraft == draft)
  #expect(result.session.revision == 11)
  #expect(result.session.confirmedCube == nil && result.session.plan == nil)
  #expect(result.palette == draft.palette)
}

@Test(
  "V11: a newer guide restores physical comparison, and complete progress restores solved confirmation"
)
func restoreNewerGuide() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  let old = ManualDraft(palette: palette, revision: request.id.revision - 1)
  try await store.saveDraft(old, lease: store.currentLease())
  try await store.save(request, palette: palette, lease: store.currentLease())
  let restored = try await store.restore()
  #expect(restored.session.phase == .resumeCheck)
  #expect(restored.session.guideProgress == request.progress)
  #expect(!restored.session.aligned && restored.session.preview == .idle)
  #expect(restored.palette == palette)
  let complete = try GuideProgress(
    plan: request.progress.plan, revision: request.id.revision,
    acknowledgedActions: request.progress.actions.count)
  let last = GuideSaveRequest(
    id: SaveID(revision: request.id.revision, sequence: 99),
    kind: .acknowledgement, progress: complete, pendingPrepared: false)
  try await store.save(last, palette: palette, lease: store.currentLease())
  #expect(try await store.restore().session.phase == .expectedSolved)
}

@Test("V11: a newer draft supersedes old guide instructions without silently validating input")
func restoreNewerDraft() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(request, palette: palette, lease: store.currentLease())
  let draft = ManualDraft(palette: palette, revision: request.id.revision + 1)
  try await store.saveDraft(draft, lease: store.currentLease())
  let restored = try await store.restore()
  #expect(restored.session.phase == .editing)
  #expect(restored.session.draft == draft)
  #expect(restored.session.guideProgress == nil && restored.session.confirmedCube == nil)
  #expect(try await store.load()?.progress == request.progress)
  let editing = SessionReducer.reduce(
    restored.session,
    event: .editDraft(.sticker(face: .front, row: 0, column: 0, color: .blue))
  ).session
  let save = try #require(editing.pendingDraftSave)
  try await store.saveDraft(save.draft, lease: restored.lease)
  #expect(try await store.loadDraft()?.revision == draft.revision + 1)
}

@Test("V11: equal revisions require identical original colors and palette before restoring a guide")
func restoreEqualRevisionConflict() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(guide, palette: palette, lease: store.currentLease())
  let matching = try filledDraft(guide.progress.plan.original, palette: palette).rebased(
    to: guide.id.revision)
  try await store.saveDraft(matching, lease: store.currentLease())
  #expect(try await store.restore().session.phase == .resumeCheck)
  let differentPalette = try CenterPalette([.white, .yellow, .red, .orange, .blue, .green])
  let conflicting = [
    ManualDraft(palette: palette, revision: guide.id.revision),
    try filledDraft(.solved, palette: palette).rebased(to: guide.id.revision),
    try filledDraft(guide.progress.plan.original, palette: differentPalette).rebased(
      to: guide.id.revision),
  ]
  let path = directory.appendingPathComponent("draft.json")
  for draft in conflicting {
    let bytes = try DraftArchive.encode(draft)
    try bytes.write(to: path)
    await #expect(throws: SessionStoreError.conflictingRecords) { try await store.restore() }
    #expect(try Data(contentsOf: path) == bytes)
    #expect(try await store.load()?.progress == guide.progress)
  }
}

@Test("V11: an unreadable record is not silently discarded during restore")
func restoreCorruptRecord() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let guide = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(guide, palette: palette, lease: store.currentLease())
  let bad = Data("broken draft".utf8)
  let draftFile = directory.appendingPathComponent("draft.json")
  try bad.write(to: draftFile)
  await #expect(throws: (any Error).self) { try await store.restore() }
  #expect(try Data(contentsOf: draftFile) == bad)
  #expect(try await store.load()?.progress == guide.progress)
}

@Test("V15: restoration carries a lease that becomes invalid when deletion completes")
func restoreLeaseInvalidation() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let draft = ManualDraft(palette: try archivePalette(), revision: 4)
  try await store.saveDraft(draft, lease: store.currentLease())
  let snapshot = try await store.restore()
  _ = try await store.delete(lease: snapshot.lease)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.saveDraft(draft, lease: snapshot.lease)
  }
  #expect(try await store.restore().session.phase == .home)
}
