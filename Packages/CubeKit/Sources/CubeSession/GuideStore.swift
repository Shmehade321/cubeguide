import Darwin
import Foundation

public enum GuideStoreError: Error, Equatable {
  case staleLease, staleWrite, existingArchiveNeedsReview
}
public struct StorageLease: Equatable, Sendable {
  fileprivate let value: UUID
}
enum StoreBoundary: CaseIterable, Sendable {
  case beforeWrite, temporarySynced, beforeReplace, afterReplace, beforeDelete
}
/// One instance owns the guide directory; callers retain its lease for each asynchronous producer.
public actor GuideStore {
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
    protection: @escaping @Sendable (URL) throws -> Void = GuideStore.applyProtection
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
  public func currentLease() -> StorageLease { lease }
  private var file: URL { directory.appendingPathComponent("guide.json") }
  private var temporary: URL { directory.appendingPathComponent("guide.pending") }
  private func syncDirectory() throws {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
  }
  public func load() throws -> RestoredGuide? {
    let descriptor = Darwin.open(file.path, O_RDONLY)
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: GuideArchive.maximumBytes + 1) ?? Data()
    return try GuideArchive.decode(bytes)
  }
  public func save(_ request: GuideSaveRequest, palette: CenterPalette, lease: StorageLease) throws
  {
    guard lease == self.lease else { throw GuideStoreError.staleLease }
    let existing: RestoredGuide?
    do { existing = try load() } catch { throw GuideStoreError.existingArchiveNeedsReview }
    if let existing {
      guard request.id.revision >= existing.saveID.revision else {
        throw GuideStoreError.staleWrite
      }
      if request.id.revision == existing.saveID.revision {
        guard request.id.sequence >= existing.saveID.sequence else {
          throw GuideStoreError.staleWrite
        }
        if request.id.sequence == existing.saveID.sequence {
          guard request.progress == existing.progress, palette == existing.palette,
            request.pendingPrepared == existing.pendingPrepared
          else { throw GuideStoreError.staleWrite }
        }
      }
    }
    let bytes = try GuideArchive.encode(request, palette: palette)
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
    guard lease == self.lease else { throw GuideStoreError.staleLease }
    self.lease = StorageLease(value: UUID())
    try checkpoint(.beforeDelete)
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
    if FileManager.default.fileExists(atPath: temporary.path) {
      try FileManager.default.removeItem(at: temporary)
    }
    if FileManager.default.fileExists(atPath: directory.path) { try syncDirectory() }
    return self.lease
  }
}
