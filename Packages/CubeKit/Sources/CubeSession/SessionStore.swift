import Darwin
import Foundation

public enum SessionStoreError: Error, Equatable {
  case staleLease, staleWrite, existingArchiveNeedsReview, conflictingRecords
}
public struct StorageLease: Equatable, Sendable {
  fileprivate let value: UUID
}
package enum StoreBoundary: String, CaseIterable, Sendable {
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
  package init(
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
      let draft = try loadDraftRecord()
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
    var record = try loadDraftRecord()
    let latest = max(boundary ?? 0, guide?.saveID.revision ?? 0, record?.revision ?? 0)
    if let boundary {
      if let existing = guide, existing.saveID.revision <= boundary { guide = nil }
      if let existing = record, existing.revision <= boundary { record = nil }
    }
    var draft: ManualDraft?
    var pendingScan: PendingScan?
    switch record {
    case .manual(let value): draft = value
    case .scan(let scan):
      if let guide, guide.saveID.revision == scan.draft.revision {
        throw SessionStoreError.conflictingRecords
      }
      // A newer confirmed guide has accepted replacement of the older input draft.
      if guide.map({ $0.saveID.revision < scan.draft.revision }) ?? true {
        try validateScanBinding(scan, guide: guide)
        pendingScan = scan
      }
    case .discarded(let marker): try validateDiscardBinding(marker, guide: guide)
    case nil: break
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
          session: Session(restoring: guide).retainingInputRevision(latest), palette: guide.palette,
          lease: lease,
          pendingScan: pendingScan, retainedGuideID: guide.saveID)
      }
    }
    if let draft {
      return SessionRestoration(
        session: Session(restoringDraft: draft).retainingInputRevision(latest),
        palette: draft.palette, lease: lease,
        pendingScan: pendingScan, retainedGuideID: guide?.saveID)
    }
    if case .discarded = record {
      return SessionRestoration(
        session: Session().retainingInputRevision(latest), palette: nil, lease: lease)
    }
    if let boundary {
      return SessionRestoration(
        session: Session(restoringManualStart: boundary).retainingInputRevision(latest),
        palette: nil, lease: lease,
        pendingScan: pendingScan)
    }
    return SessionRestoration(
      session: Session().retainingInputRevision(latest), palette: nil, lease: lease,
      pendingScan: pendingScan)
  }
  private func loadDraftRecord() throws -> DraftRecord? {
    guard let bytes = try read(draftFile) else { return nil }
    return try DraftArchive.decodeRecord(bytes)
  }
  public func loadDraft() throws -> ManualDraft? {
    guard case .manual(let draft) = try loadDraftRecord() else { return nil }
    return draft
  }
  public func loadScanDraft() throws -> PendingScan? {
    guard case .scan(let scan) = try loadDraftRecord() else { return nil }
    return scan
  }
  private func validateScanBinding(_ scan: PendingScan, guide: RestoredGuide?) throws {
    guard scan.retainedGuide == guide?.saveID else { throw SessionStoreError.conflictingRecords }
    if scan.purpose == .verification, guide?.progress.isComplete != true {
      throw SessionStoreError.conflictingRecords
    }
  }
  private func checkDraftOrdering(_ candidate: DraftRecord) throws {
    let existing: DraftRecord?
    do { existing = try loadDraftRecord() } catch {
      throw SessionStoreError.existingArchiveNeedsReview
    }
    if let existing {
      guard candidate.revision > existing.revision || candidate == existing else {
        throw SessionStoreError.staleWrite
      }
    }
  }
  public func saveScanDraft(_ scan: PendingScan, lease: StorageLease) throws {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    try checkManualStartBoundary(scan.draft.revision)
    try checkDraftOrdering(.scan(scan))
    var guide = try load()
    if let boundary = try loadManualStart(), let existing = guide,
      existing.saveID.revision <= boundary
    {
      guide = nil
    }
    try validateScanBinding(scan, guide: guide)
    try replace(DraftArchive.encode(scan), file: draftFile, temporary: draftTemporary)
  }
  public func saveDraft(_ draft: ManualDraft, lease: StorageLease) throws {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    try checkManualStartBoundary(draft.revision)
    try checkDraftOrdering(.manual(draft))
    let bytes = try DraftArchive.encode(draft)
    try replace(bytes, file: draftFile, temporary: draftTemporary)
  }
  private func validateDiscardBinding(_ marker: DiscardedDraft, guide: RestoredGuide?) throws {
    if let guide, guide.saveID.revision > marker.revision { return }
    if let retained = marker.retainedGuide {
      guard let guide, guide.saveID.revision == retained.revision,
        guide.saveID.sequence >= retained.sequence
      else { throw SessionStoreError.conflictingRecords }
    } else if guide != nil {
      throw SessionStoreError.conflictingRecords
    }
  }
  public func discardDraft(revision: UInt64, lease: StorageLease) throws -> StorageLease {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    let boundary = try loadManualStart()
    let record = try loadDraftRecord()
    var guide = try load()
    let latest = max(boundary ?? 0, record?.revision ?? 0, guide?.saveID.revision ?? 0)
    if let boundary, let existing = guide, existing.saveID.revision <= boundary { guide = nil }
    let marker: DiscardedDraft
    if case .discarded(let existing) = record, existing.revision == revision {
      guard revision > (boundary ?? 0), guide.map({ $0.saveID.revision < revision }) ?? true else {
        throw SessionStoreError.staleWrite
      }
      try validateDiscardBinding(existing, guide: guide)
      marker = existing
    } else {
      guard revision > latest else { throw SessionStoreError.staleWrite }
      marker = try DiscardedDraft(revision: revision, retainedGuide: guide?.saveID)
    }
    let bytes = try CheckedArchive.encode(DraftRecord.discarded(marker))
    self.lease = StorageLease(value: UUID())
    try replace(bytes, file: draftFile, temporary: draftTemporary)
    return self.lease
  }
  public func loadPreferences() throws -> AppPreferences {
    guard let bytes = try read(preferencesFile) else { return AppPreferences() }
    return try CheckedArchive.decode(AppPreferences.self, from: bytes)
  }
  public func savePreferences(_ preferences: AppPreferences, lease: StorageLease) throws {
    guard lease == self.lease else { throw SessionStoreError.staleLease }
    // Preserve corrupt or newer settings until explicit local-data deletion.
    _ = try loadPreferences()
    try replace(CheckedArchive.encode(preferences), file: preferencesFile,
      temporary: preferencesTemporary)
  }
  private var preferencesFile: URL { directory.appendingPathComponent("preferences.json") }
  private var preferencesTemporary: URL { directory.appendingPathComponent("preferences.pending") }
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
    if case .scan(let scan) = try loadDraftRecord(), scan.draft.revision >= request.id.revision {
      guard scan.draft.revision > request.id.revision, scan.retainedGuide == request.id else {
        throw SessionStoreError.conflictingRecords
      }
    }
    if case .discarded(let marker) = try loadDraftRecord(), request.id.revision <= marker.revision {
      try validateDiscardBinding(marker, guide: load())
      guard request.id.revision == marker.retainedGuide?.revision else {
        throw SessionStoreError.staleWrite
      }
    }
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
            request.pendingPrepared == existing.pendingPrepared,
            request.kind.completion == existing.completion,
            (request.kind == .recovery) == existing.recoveryRequired
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
      preferencesFile, preferencesTemporary,
    ] {
      if FileManager.default.fileExists(atPath: ownedFile.path) {
        try FileManager.default.removeItem(at: ownedFile)
      }
    }
    if FileManager.default.fileExists(atPath: directory.path) { try syncDirectory() }
    return self.lease
  }
}
