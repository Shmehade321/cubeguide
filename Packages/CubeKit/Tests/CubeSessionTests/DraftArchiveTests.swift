import CubeCore
import Foundation
import Testing

@testable import CubeSession

@Test("V11: versioned draft archive preserves incomplete input and rejects corruption")
func draftArchiveRoundTrip() throws {
  let draft = try ManualDraft(palette: archivePalette(), revision: 42)
    .setting(face: .left, row: 0, column: 2, color: .blue)
  let bytes = try DraftArchive.encode(draft)
  #expect(bytes.count > 0 && bytes.count < DraftArchive.maximumBytes)
  #expect(try DraftArchive.decode(bytes) == draft)
  #expect(throws: ArchiveError.unsupportedVersion) {
    try DraftArchive.decode(mutatedArchive(bytes, envelope: { $0["schema"] = 2 }))
  }
  #expect(throws: ArchiveError.corrupt) {
    try DraftArchive.decode(mutatedArchive(bytes, envelope: { $0["checksum"] = "wrong" }))
  }
  #expect(throws: ArchiveError.sizeLimit) {
    try DraftArchive.decode(Data(repeating: 32, count: DraftArchive.maximumBytes + 1))
  }
  #expect(throws: (any Error).self) {
    try DraftArchive.decode(mutatedArchive(bytes, payload: { $0["cells"] = [] }))
  }
}
