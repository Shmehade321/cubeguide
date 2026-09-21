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
  case discarded(DiscardedDraft)
  var revision: UInt64 {
    switch self {
    case .manual(let draft): draft.revision
    case .scan(let scan): scan.draft.revision
    case .discarded(let marker): marker.revision
    }
  }
  private enum CodingKeys: String, CodingKey { case kind, scan, discarded }
  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    if values.contains(.kind) {
      switch try values.decode(String.self, forKey: .kind) {
      case "scan": self = .scan(try values.decode(PendingScan.self, forKey: .scan))
      case "discarded":
        self = .discarded(try values.decode(DiscardedDraft.self, forKey: .discarded))
      default: throw ArchiveError.unsupportedVersion
      }
    } else {
      self = .manual(try ManualDraft(from: decoder))
    }
  }
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .discarded(let marker):
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode("discarded", forKey: .kind)
      try values.encode(marker, forKey: .discarded)
    case .manual(let draft): try draft.encode(to: encoder)
    case .scan(let scan):
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode("scan", forKey: .kind)
      try values.encode(scan, forKey: .scan)
    }
  }
}

/// Contains no discarded colors or measurements. Retains the ordering boundary across relaunch.
struct DiscardedDraft: Equatable, Sendable, Codable {
  let revision: UInt64
  let retainedGuide: SaveID?
  init(revision: UInt64, retainedGuide: SaveID?) throws {
    guard revision > 0 else { throw ArchiveError.invalidProgress }
    if let retainedGuide {
      guard retainedGuide.sequence > 0, retainedGuide.revision < revision else {
        throw ArchiveError.invalidProgress
      }
    }
    self.revision = revision
    self.retainedGuide = retainedGuide
  }
  private enum CodingKeys: String, CodingKey { case revision, retainedGuide }
  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      revision: values.decode(UInt64.self, forKey: .revision),
      retainedGuide: values.decodeIfPresent(SaveID.self, forKey: .retainedGuide))
  }
}
