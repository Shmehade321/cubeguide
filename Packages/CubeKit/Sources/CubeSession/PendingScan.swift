import CubeScan
import Foundation

public enum ScanPurpose: String, Sendable, Codable { case newCube, recovery, verification }

/// A draft is not permission to replace the retained guide or proof of a physical solve.
public struct PendingScan: Equatable, Sendable, Codable {
  public let draft: ScanDraft
  public let purpose: ScanPurpose
  public let retainedGuide: SaveID?
  public init(draft: ScanDraft, purpose: ScanPurpose, retainedGuide: SaveID? = nil) throws {
    guard purpose == .newCube || retainedGuide != nil else { throw ArchiveError.invalidProgress }
    if let retainedGuide {
      guard retainedGuide.sequence > 0, retainedGuide.revision < draft.revision else {
        throw ArchiveError.invalidProgress
      }
    }
    self.draft = draft
    self.purpose = purpose
    self.retainedGuide = retainedGuide
  }
  private enum CodingKeys: String, CodingKey { case draft, purpose, retainedGuide }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      draft: values.decode(ScanDraft.self, forKey: .draft),
      purpose: values.decode(ScanPurpose.self, forKey: .purpose),
      retainedGuide: values.decodeIfPresent(SaveID.self, forKey: .retainedGuide))
  }
}
