import Foundation

public enum DraftArchive {
  public static let maximumBytes = CheckedArchive.maximumBytes
  public static func encode(_ draft: ManualDraft) throws -> Data {
    try CheckedArchive.encode(draft)
  }
  public static func decode(_ data: Data) throws -> ManualDraft {
    guard case .manual(let draft) = try decodeRecord(data) else {
      throw ArchiveError.invalidProgress
    }
    return draft
  }
  public static func encode(_ scan: PendingScan) throws -> Data {
    try CheckedArchive.encode(DraftRecord.scan(scan))
  }
  public static func decodeScan(_ data: Data) throws -> PendingScan {
    guard case .scan(let scan) = try decodeRecord(data) else { throw ArchiveError.invalidProgress }
    return scan
  }
  static func decodeRecord(_ data: Data) throws -> DraftRecord {
    try CheckedArchive.decode(DraftRecord.self, from: data)
  }
}

/// Legacy manual payloads are unchanged. New kinds must be explicitly understood, never guessed.
enum DraftRecord: Equatable, Sendable, Codable {
  case manual(ManualDraft)
  case scan(PendingScan)
  var revision: UInt64 {
    switch self {
    case .manual(let draft): draft.revision
    case .scan(let scan): scan.draft.revision
    }
  }
  private enum CodingKeys: String, CodingKey { case kind, scan }
  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    if values.contains(.kind) {
      guard try values.decode(String.self, forKey: .kind) == "scan" else {
        throw ArchiveError.unsupportedVersion
      }
      self = .scan(try values.decode(PendingScan.self, forKey: .scan))
    } else {
      self = .manual(try ManualDraft(from: decoder))
    }
  }
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .manual(let draft): try draft.encode(to: encoder)
    case .scan(let scan):
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode("scan", forKey: .kind)
      try values.encode(scan, forKey: .scan)
    }
  }
}
