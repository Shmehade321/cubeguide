import Foundation

/// A committed manual-entry boundary before any explicit center palette exists.
/// Older guide/draft files remain bounded records, but cannot be resumed or rewritten.
enum ManualStartArchive {
  private struct Record: Codable { let revision: UInt64 }
  static func encode(revision: UInt64) throws -> Data {
    guard revision > 0 else { throw ArchiveError.invalidProgress }
    return try CheckedArchive.encode(Record(revision: revision))
  }
  static func decode(_ bytes: Data) throws -> UInt64 {
    let revision = try CheckedArchive.decode(Record.self, from: bytes).revision
    guard revision > 0 else { throw ArchiveError.invalidProgress }
    return revision
  }
}
