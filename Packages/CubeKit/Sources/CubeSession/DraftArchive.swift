import Foundation

public enum DraftArchive {
  public static let maximumBytes = CheckedArchive.maximumBytes
  public static func encode(_ draft: ManualDraft) throws -> Data {
    try CheckedArchive.encode(draft)
  }
  public static func decode(_ data: Data) throws -> ManualDraft {
    try CheckedArchive.decode(ManualDraft.self, from: data)
  }
}
