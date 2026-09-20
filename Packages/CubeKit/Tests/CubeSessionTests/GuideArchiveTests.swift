import CryptoKit
import CubeCore
import Foundation
import Testing

@testable import CubeSession

func archivePalette() throws -> CenterPalette {
  try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
}

@Test("V11: archive restores verified progress, exact regrip identity and explicit centers")
func archiveRoundTrip() throws {
  let initial = try preparingSession()
  let initialRequest = try #require(initial.pendingSave)
  let palette = try archivePalette()
  for offset in 0...initialRequest.progress.actions.count {
    let progress = try GuideProgress(
      plan: initialRequest.progress.plan,
      revision: initial.revision, acknowledgedActions: offset)
    for prepared in [false, true] where !prepared || !progress.isComplete {
      let request = GuideSaveRequest(
        id: SaveID(revision: initial.revision, sequence: UInt64(offset + 1)),
        kind: prepared ? .preparation : .acknowledgement,
        progress: progress, pendingPrepared: prepared)
      let bytes = try GuideArchive.encode(request, palette: palette)
      #expect(bytes.count > 0 && bytes.count <= GuideArchive.maximumBytes)
      let restored = try GuideArchive.decode(bytes)
      #expect(restored.progress == progress)
      #expect(restored.palette == palette)
      #expect(restored.saveID == request.id)
      #expect(restored.pendingPrepared == prepared)
    }
  }
}

// Re-sign deliberately inconsistent payloads: a checksum is not semantic validation.
func mutatedArchive(
  _ bytes: Data, resign: Bool = true,
  envelope changeEnvelope: (inout [String: Any]) -> Void = { _ in },
  payload changePayload: (inout [String: Any]) -> Void = { _ in }
) throws -> Data {
  var envelope = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  let encoded = try #require(envelope["payload"] as? String)
  let data = try #require(Data(base64Encoded: encoded))
  var payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  changePayload(&payload)
  let altered = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  envelope["payload"] = altered.base64EncodedString()
  if resign {
    envelope["checksum"] = SHA256.hash(data: altered).map { String(format: "%02x", $0) }.joined()
  }
  changeEnvelope(&envelope)
  return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

@Test("V11: archive checks schema, checksum and whole-file size before restoration")
func archiveEnvelopeGuards() throws {
  let request = try #require(try preparingSession().pendingSave)
  let bytes = try GuideArchive.encode(request, palette: archivePalette())
  #expect(throws: ArchiveError.unsupportedVersion) {
    try GuideArchive.decode(mutatedArchive(bytes, envelope: { $0["schema"] = 2 }))
  }
  #expect(throws: ArchiveError.corrupt) {
    try GuideArchive.decode(
      mutatedArchive(bytes, envelope: { $0["checksum"] = String(repeating: "0", count: 64) }))
  }
  #expect(throws: ArchiveError.sizeLimit) {
    try GuideArchive.decode(Data(repeating: 32, count: GuideArchive.maximumBytes + 1))
  }
  for data in [Data(), Data(bytes.dropLast()), Data("null".utf8)] {
    #expect(throws: (any Error).self) { try GuideArchive.decode(data) }
  }
}

@Test("V11: correctly checksummed archives must reconstruct exact state, pose and pending identity")
func archiveSemanticGuards() throws {
  let request = try #require(try preparingSession().pendingSave)
  let bytes = try GuideArchive.encode(request, palette: archivePalette())
  let mutations: [(inout [String: Any]) -> Void] = [
    { $0["originalHash"] = String(repeating: "0", count: 64) },
    { $0["resourceVersion"] = "" },
    { $0["resourceVersion"] = String(repeating: "x", count: 257) },
    { $0["moveIndex"] = 1 },
    { $0["acknowledgedActions"] = -1 },
    { $0["acknowledgedActions"] = 91 },
    { $0["state"] = Facelets.solved.notation },
    { $0["pose"] = [0, 5, 1, 3, 2, 4] },
    {
      $0["pendingAction"] = [
        "sessionRevision": request.id.revision, "moveIndex": 0, "actionIndex": 1,
      ]
    },
    { $0["pendingAction"] = NSNull() },
    { $0["saveID"] = ["revision": request.id.revision, "sequence": 0] },
    { $0["moves"] = "" },
    { $0["moves"] = Array(repeating: "R", count: 31).joined(separator: " ") },
    { $0["original"] = String(repeating: "U", count: 54) },
  ]
  for (index, mutation) in mutations.enumerated() {
    #expect(throws: (any Error).self, "Mutation \(index) must be rejected") {
      try GuideArchive.decode(mutatedArchive(bytes, payload: mutation))
    }
  }
}

@Test("V11: restoring opens physical comparison and never resumes preview automatically")
func archiveSessionRestore() throws {
  let request = try #require(try preparingSession().pendingSave)
  for offset in 0...request.progress.actions.count {
    let progress = try GuideProgress(
      plan: request.progress.plan, revision: request.progress.revision,
      acknowledgedActions: offset)
    for prepared in [false, true] where !prepared || !progress.isComplete {
      let save = GuideSaveRequest(
        id: SaveID(revision: progress.revision, sequence: 42),
        kind: prepared ? .preparation : .acknowledgement,
        progress: progress, pendingPrepared: prepared)
      let archive = try GuideArchive.decode(GuideArchive.encode(save, palette: archivePalette()))
      let session = try Session(restoring: archive)
      #expect(session.phase == (progress.isComplete ? .expectedSolved : .resumeCheck))
      #expect(session.guideProgress == progress)
      #expect(session.hasWork)
      #expect(session.confirmedCube?.facelets == progress.plan.original)
      #expect(!session.aligned && session.preview == .idle && session.playbackID == nil)
      #expect(session.pendingSave == nil)
      #expect(session.preparationDurable == prepared)
      #expect(apply(session, .play).disposition == .rejected(.unavailableEvent))
      if !progress.isComplete {
        let checked = apply(session, .compare(prepared ? .after : .before)).session
        let retry = try #require(checked.pendingSave)
        #expect(retry.id.sequence == 43)
        #expect(apply(checked, .persisted(save.id)).disposition == .ignored)
      }
    }
  }
}
