import CubeCore
import Foundation
import Testing

@testable import CubeSession

@Test("V11: partial draft and active guide survive together across reopen")
func draftStoreRoundTrip() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  #expect(try await store.loadDraft() == nil)
  let guide = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(guide, palette: palette, lease: store.currentLease())
  let draft = try ManualDraft(palette: palette, revision: 11)
    .setting(face: .down, row: 0, column: 0, color: .blue)
  try await store.saveDraft(draft, lease: store.currentLease())
  let reopened = SessionStore(directory: directory)
  #expect(try await reopened.loadDraft() == draft)
  #expect(try await reopened.load()?.progress == guide.progress)
  let bytes = try Data(contentsOf: directory.appendingPathComponent("draft.json"))
  #expect(try DraftArchive.decode(bytes) == draft)
}

@Test("V11: draft saves reject stale and conflicting revisions without changing durable data")
func draftStoreOrdering() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let original = ManualDraft(palette: try archivePalette(), revision: 4)
  let newer = try original.setting(face: .front, row: 0, column: 0, color: .blue)
  try await store.saveDraft(newer, lease: store.currentLease())
  for invalid in [original, ManualDraft(palette: original.palette, revision: newer.revision)] {
    await #expect(throws: SessionStoreError.staleWrite) {
      try await store.saveDraft(invalid, lease: store.currentLease())
    }
    #expect(try await store.loadDraft() == newer)
  }
  try await store.saveDraft(newer, lease: store.currentLease())
  #expect(try await store.loadDraft() == newer)
}

@Test("V15: one deletion invalidates guide and draft producers and removes both pending files")
func draftStoreDeletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let lease = await store.currentLease()
  let palette = try archivePalette()
  let draft = ManualDraft(palette: palette)
  let guide = try #require(try preparingSession().pendingSave)
  try await store.saveDraft(draft, lease: lease)
  try await store.save(guide, palette: palette, lease: lease)
  for name in ["guide.pending", "draft.pending"] {
    try Data("partial".utf8).write(to: directory.appendingPathComponent(name))
  }
  _ = try await store.delete(lease: lease)
  #expect(try await store.load() == nil)
  #expect(try await store.loadDraft() == nil)
  for name in ["guide.json", "guide.pending", "draft.json", "draft.pending"] {
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
  }
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.saveDraft(draft, lease: lease)
  }
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.save(guide, palette: palette, lease: lease)
  }
}

@Test("V11: unreadable draft is preserved until explicit discard, without damaging the guide")
func draftStorePreservesUnknown() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let draft = ManualDraft(palette: try archivePalette())
  let good = try DraftArchive.encode(draft)
  let newer = try mutatedArchive(good, envelope: { $0["schema"] = 2 })
  let guide = try #require(try preparingSession().pendingSave)
  try await store.save(guide, palette: draft.palette, lease: store.currentLease())
  for bytes in [Data("invalid".utf8), newer] {
    let path = directory.appendingPathComponent("draft.json")
    try bytes.write(to: path)
    await #expect(throws: (any Error).self) { try await store.loadDraft() }
    await #expect(throws: SessionStoreError.existingArchiveNeedsReview) {
      try await store.saveDraft(draft, lease: store.currentLease())
    }
    #expect(try Data(contentsOf: path) == bytes)
    #expect(try await store.load()?.progress == guide.progress)
  }
}

private enum DraftWriteFailure: Error { case interrupted }

@Test("V11: interrupted draft writes preserve a valid old/new draft and leave the guide unchanged")
func draftStoreWriteBoundaries() async throws {
  let palette = try archivePalette()
  let original = ManualDraft(palette: palette, revision: 9)
  let next = try original.setting(face: .back, row: 2, column: 2, color: .red)
  let guide = try #require(try preparingSession().pendingSave)
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    try await store.saveDraft(original, lease: store.currentLease())
    try await store.save(guide, palette: palette, lease: store.currentLease())
    let interrupted = SessionStore(directory: directory) { stage in
      if stage == boundary { throw DraftWriteFailure.interrupted }
    }
    await #expect(throws: DraftWriteFailure.self) {
      try await interrupted.saveDraft(next, lease: interrupted.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    #expect(try await reopened.loadDraft() == (boundary == .afterReplace ? next : original))
    #expect(try await reopened.load()?.progress == guide.progress)
  }
}
