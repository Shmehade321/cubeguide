import Darwin
import Foundation

public enum SessionStoreError: Error, Equatable {
  case staleLease, staleWrite, existingArchiveNeedsReview, conflictingRecords
}
public struct StorageLease: Equatable, Sendable {
  fileprivate let value: UUID
}
enum StoreBoundary: CaseIterable, Sendable {
  case beforeWrite, temporarySynced, beforeReplace, afterReplace, beforeDelete
}
/// One instance owns guide and draft files in its directory; callers retain its lease for each asynchronous producer.
public actor SessionStore {
  private let directory: URL
  private var lease = StorageLease(value: UUID())
  private let checkpoint: @Sendable (StoreBoundary) throws -> Void
  private let protection: @Sendable (URL) throws -> Void
  public init(directory: URL) {
    self.directory = directory
    self.checkpoint = { _ in }
    self.protection = Self.applyProtection
  }
  init(
    directory: URL, checkpoint: @escaping @Sendable (StoreBoundary) throws -> Void,
    protection: @escaping @Sendable (URL) throws -> Void = SessionStore.applyProtection
  ) {
    self.directory = directory
    self.checkpoint = checkpoint
    self.protection = protection
  }
  private static func applyProtection(_ url: URL) throws {
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    #endif
  }
  public func startManual(revision: UInt64, lease: StorageLease) throws {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    let previous = try loadManualStart()
    if previous != revision {
      let guide = try load()
      let draft = try loadDraft()
      let latest = max(previous ?? 0, guide?.saveID.revision ?? 0, draft?.revision ?? 0)
      guard revision > latest else { throw SessionStoreError.staleWrite }
    }
    // Repeat synchronization even if a prior failed callback left this marker in place.
    // Rewriting the same boundary cannot discard a newer draft or guide.
    try replace(
      ManualStartArchive.encode(revision: revision),
      file: manualStartFile, temporary: manualStartTemporary)
  }

  private func loadManualStart() throws -> UInt64? {
    guard let bytes = try read(manualStartFile) else { return nil }
    return try ManualStartArchive.decode(bytes)
  }
  private func checkManualStartBoundary(_ revision: UInt64) throws {
    if let boundary = try loadManualStart(), revision <= boundary {
      throw SessionStoreError.staleWrite
    }
  }

  public func restore() throws -> SessionRestoration {
    // No suspension point: these reads and the lease belong to one actor snapshot.
    let boundary = try loadManualStart()
    var guide = try load()
    var draft = try loadDraft()
    if let boundary {
      if let existing = guide, existing.saveID.revision <= boundary { guide = nil }
      if let existing = draft, existing.revision <= boundary { draft = nil }
    }
    if let guide {
      if let draft, draft.revision == guide.progress.revision {
        guard draft.palette == guide.palette,
          (try? draft.canonicalFacelets()) == guide.progress.plan.original
        else { throw SessionStoreError.conflictingRecords }
      }
      let draftIsNewer = draft.map { $0.revision > guide.progress.revision } ?? false
      if !draftIsNewer {
        return try SessionRestoration(
          session: Session(restoring: guide), palette: guide.palette, lease: lease)
      }
    }
    if let draft {
      return SessionRestoration(
        session: Session(restoringDraft: draft), palette: draft.palette, lease: lease)
    }
    if let boundary {
      return SessionRestoration(
        session: Session(restoringManualStart: boundary), palette: nil, lease: lease)
    }
    return SessionRestoration(session: Session(), palette: nil, lease: lease)
  }
  public func loadDraft() throws -> ManualDraft? {
    guard let bytes = try read(draftFile) else { return nil }
    return try DraftArchive.decode(bytes)
  }
  public func saveDraft(_ draft: ManualDraft, lease: StorageLease) throws {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    try checkManualStartBoundary(draft.revision)
    let existing: ManualDraft?
    do { existing = try loadDraft() } catch { throw SessionStoreError.existingArchiveNeedsReview }
    if let existing {
      guard draft.revision > existing.revision || draft == existing else {
        throw SessionStoreError.staleWrite
      }
    }
    let bytes = try DraftArchive.encode(draft)
    try replace(bytes, file: draftFile, temporary: draftTemporary)
  }
  public func currentLease() -> StorageLease { lease }
  private var manualStartFile: URL { directory.appendingPathComponent("manual-start.json") }
  private var manualStartTemporary: URL { directory.appendingPathComponent("manual-start.pending") }
  private var file: URL { directory.appendingPathComponent("guide.json") }
  private var temporary: URL { directory.appendingPathComponent("guide.pending") }
  private var draftFile: URL { directory.appendingPathComponent("draft.json") }
  private var draftTemporary: URL { directory.appendingPathComponent("draft.pending") }
  private func syncDirectory() throws {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
  }
  public func load() throws -> RestoredGuide? {
    guard let bytes = try read(file) else { return nil }
    return try GuideArchive.decode(bytes)
  }
  private func read(_ file: URL) throws -> Data? {
    let descriptor = Darwin.open(file.path, O_RDONLY)
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: GuideArchive.maximumBytes + 1) ?? Data()
    return bytes
  }
  public func save(_ request: GuideSaveRequest, palette: CenterPalette, lease: StorageLease) throws
  {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    try checkManualStartBoundary(request.id.revision)
    let existing: RestoredGuide?
    do { existing = try load() } catch { throw SessionStoreError.existingArchiveNeedsReview }
    if let existing {
      guard request.id.revision >= existing.saveID.revision else {
        throw SessionStoreError.staleWrite
      }
      if request.id.revision == existing.saveID.revision {
        guard request.id.sequence >= existing.saveID.sequence else {
          throw SessionStoreError.staleWrite
        }
        if request.id.sequence == existing.saveID.sequence {
          guard request.progress == existing.progress, palette == existing.palette,
            request.pendingPrepared == existing.pendingPrepared
          else { throw SessionStoreError.staleWrite }
        }
      }
    }
    let bytes = try GuideArchive.encode(request, palette: palette)
    try replace(bytes, file: file, temporary: temporary)
  }
  private func replace(_ bytes: Data, file: URL, temporary: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protection(directory)
    var folder = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    try checkpoint(.beforeWrite)
    // A fixed temporary name is safe under this actor's exclusive directory ownership.
    // It is never loaded as confirmed progress, including after a process interruption.
    try Data().write(to: temporary)
    try protection(temporary)
    let handle = try FileHandle(forWritingTo: temporary)
    defer { try? handle.close() }
    try handle.write(contentsOf: bytes)
    try handle.synchronize()
    try handle.close()
    try checkpoint(.temporarySynced)
    try checkpoint(.beforeReplace)
    guard Darwin.rename(temporary.path, file.path) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    try syncDirectory()
    try checkpoint(.afterReplace)
  }
  public func delete(lease: StorageLease) throws -> StorageLease {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    self.lease = StorageLease(value: UUID())
    try checkpoint(.beforeDelete)
    for ownedFile in [
      file, temporary, draftFile, draftTemporary, manualStartFile, manualStartTemporary,
    ] {
      if FileManager.default.fileExists(atPath: ownedFile.path) {
        try FileManager.default.removeItem(at: ownedFile)
      }
    }
    if FileManager.default.fileExists(atPath: directory.path) { try syncDirectory() }
    return self.lease
  }
}
