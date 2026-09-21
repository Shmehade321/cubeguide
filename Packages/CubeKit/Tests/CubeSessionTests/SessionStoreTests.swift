import Foundation
import Testing

@testable import CubeSession

func storeDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "CubeGuide-tests-\(UUID())")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Test("V11: actual guide files survive a new store instance and preserve the explicit palette")
func storeRoundTrip() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  #expect(try await store.load() == nil)
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(request, palette: palette, lease: store.currentLease())
  let reopened = SessionStore(directory: directory)
  let loaded = try #require(try await reopened.load())
  #expect(loaded.progress == request.progress)
  #expect(loaded.palette == palette)
  #expect(loaded.pendingPrepared)
  let bytes = try Data(contentsOf: directory.appendingPathComponent("guide.json"))
  #expect(try GuideArchive.decode(bytes) == loaded)
}

@Test("V15: delete invalidates prior producer leases and prevents resurrection")
func storeDeletionLease() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let oldLease = await store.currentLease()
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(request, palette: palette, lease: oldLease)
  let newLease = try await store.delete(lease: oldLease)
  #expect(newLease != oldLease)
  #expect(try await store.load() == nil)
  #expect(
    !FileManager.default.fileExists(atPath: directory.appendingPathComponent("guide.json").path))
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.save(request, palette: palette, lease: oldLease)
  }
  await #expect(throws: SessionStoreError.staleLease) { try await store.delete(lease: oldLease) }
  #expect(try await store.load() == nil)
  try await store.save(request, palette: palette, lease: newLease)
  #expect(try await store.load()?.progress == request.progress)
}

@Test("V11: corrupt and unsupported archives survive attempted save until explicit discard")
func storePreservesUnreadableArchive() async throws {
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  let good = try GuideArchive.encode(request, palette: palette)
  let newer = try mutatedArchive(good, envelope: { $0["schema"] = 2 })
  for original in [
    Data("broken".utf8), newer, Data(repeating: 32, count: GuideArchive.maximumBytes + 1),
  ] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("guide.json")
    try original.write(to: file)
    let store = SessionStore(directory: directory)
    await #expect(throws: (any Error).self) { try await store.load() }
    await #expect(throws: SessionStoreError.existingArchiveNeedsReview) {
      try await store.save(request, palette: palette, lease: store.currentLease())
    }
    #expect(try Data(contentsOf: file) == original)
    let newLease = try await store.delete(lease: store.currentLease())
    try await store.save(request, palette: palette, lease: newLease)
    #expect(try await store.load()?.progress == request.progress)
  }
}

private enum InjectedStoreFailure: Error { case stopped }

@Test("V11: interrupted replacement leaves a complete old or new archive and reports failure")
func storeWriteBoundaries() async throws {
  let initial = try durableGuide()
  let original = try #require(try preparingSession().pendingSave)
  let action = try #require(initial.pendingAction)
  let next = try #require(apply(initial, .acknowledge(action.id)).session.pendingSave)
  let palette = try archivePalette()
  for boundary in StoreBoundary.allCases where boundary != .beforeDelete {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(directory: directory)
    try await store.save(original, palette: palette, lease: store.currentLease())
    let failing = SessionStore(directory: directory) { stage in
      if stage == boundary { throw InjectedStoreFailure.stopped }
    }
    await #expect(throws: InjectedStoreFailure.self) {
      try await failing.save(next, palette: palette, lease: failing.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    let recovered = try #require(try await reopened.load())
    #expect(recovered.progress == (boundary == .afterReplace ? next.progress : original.progress))
    // A failed callback is ambiguous only at/after replacement; either archive is fully verified.
    try await reopened.save(next, palette: palette, lease: reopened.currentLease())
    #expect(try await reopened.load()?.progress == next.progress)
  }
}

@Test("V15: failed deletion is reported and still invalidates old producers")
func storeDeleteFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory) { boundary in
    if boundary == .beforeDelete { throw InjectedStoreFailure.stopped }
  }
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  let lease = await store.currentLease()
  try await store.save(request, palette: palette, lease: lease)
  await #expect(throws: InjectedStoreFailure.self) { try await store.delete(lease: lease) }
  #expect(try await store.load()?.progress == request.progress)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.save(request, palette: palette, lease: lease)
  }
}

@Test("V11: abandoned temporary bytes are never promoted to confirmed progress")
func storeAbandonedTemporaryAndIOFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let pending = directory.appendingPathComponent("guide.pending")
  try Data("partial interrupted write".utf8).write(to: pending)
  let store = SessionStore(directory: directory)
  #expect(try await store.load() == nil)
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(request, palette: palette, lease: store.currentLease())
  #expect(!FileManager.default.fileExists(atPath: pending.path))
  // A real OS write failure (destination is a directory), without fake storage success.
  try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
  await #expect(throws: (any Error).self) {
    try await store.save(request, palette: palette, lease: store.currentLease())
  }
  #expect(try await store.load()?.progress == request.progress)
  _ = try await store.delete(lease: store.currentLease())
  #expect(!FileManager.default.fileExists(atPath: pending.path))
}

@Test("V11: an older save cannot overwrite newer durable acknowledgement")
func storeRejectsReorderedWrites() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let original = try #require(try preparingSession().pendingSave)
  let guide = try durableGuide()
  let action = try #require(guide.pendingAction)
  let next = try #require(apply(guide, .acknowledge(action.id)).session.pendingSave)
  let palette = try archivePalette()
  try await store.save(next, palette: palette, lease: store.currentLease())
  await #expect(throws: (any Error).self) {
    try await store.save(original, palette: palette, lease: store.currentLease())
  }
  #expect(try await store.load()?.progress == next.progress)
  let altered = GuideSaveRequest(
    id: next.id, kind: .preparation,
    progress: original.progress, pendingPrepared: true)
  await #expect(throws: (any Error).self) {
    try await store.save(altered, palette: palette, lease: store.currentLease())
  }
  #expect(try await store.load()?.progress == next.progress)
}

@Test("V15: guide storage is excluded from backups")
func storeBackupExclusion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let request = try #require(try preparingSession().pendingSave)
  try await store.save(request, palette: archivePalette(), lease: store.currentLease())
  let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
  #expect(values.isExcludedFromBackup == true)
}

@Test("V15: deletion serializes after an in-flight replacement and rejects late old producers")
func storeDeleteDuringWrite() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let store = SessionStore(directory: directory) { boundary in
    if boundary == .beforeReplace {
      entered.signal()
      release.wait()
    }
  }
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  let lease = await store.currentLease()
  let write = Task { try await store.save(request, palette: palette, lease: lease) }
  let reachedBoundary = await Task.detached { waitForStoreBoundary(entered) }.value
  guard reachedBoundary else {
    release.signal()
    Issue.record("Write never reached the controlled replacement boundary")
    try await write.value
    return
  }
  let deletion = Task { try await store.delete(lease: lease) }
  release.signal()
  try await write.value
  _ = try await deletion.value
  #expect(try await store.load() == nil)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.save(request, palette: palette, lease: lease)
  }
  #expect(try await SessionStore(directory: directory).load() == nil)
}

private func waitForStoreBoundary(_ semaphore: DispatchSemaphore) -> Bool {
  semaphore.wait(timeout: .now() + 10) == .success
}

@Test(
  "V11: inaccessible directories are storage errors, never an absent session or successful deletion"
)
func storePermissionFailure() async throws {
  let directory = try storeDirectory()
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
  }
  let store = SessionStore(directory: directory)
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  try await store.save(request, palette: palette, lease: store.currentLease())
  try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)
  await #expect(throws: (any Error).self) { try await store.load() }
  await #expect(throws: (any Error).self) {
    try await store.save(request, palette: palette, lease: store.currentLease())
  }
  await #expect(throws: (any Error).self) { try await store.delete(lease: store.currentLease()) }
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  #expect(try await store.load()?.progress == request.progress)
}

@Test("V15: protection failure aborts before payload data is written or replaces an archive")
func storeProtectionFailure() async throws {
  let request = try #require(try preparingSession().pendingSave)
  let palette = try archivePalette()
  for failAtTemporary in [false, true] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionStore(
      directory: directory, checkpoint: { _ in },
      protection: { url in
        if !failAtTemporary || url.lastPathComponent == "guide.pending" {
          throw InjectedStoreFailure.stopped
        }
      })
    await #expect(throws: InjectedStoreFailure.self) {
      try await store.save(request, palette: palette, lease: store.currentLease())
    }
    #expect(try await store.load() == nil)
    let pending = directory.appendingPathComponent("guide.pending")
    if FileManager.default.fileExists(atPath: pending.path) {
      #expect(try Data(contentsOf: pending).isEmpty)
    }
  }
}
