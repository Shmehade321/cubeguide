import CubeCore
import CubeScan
import Foundation
import Testing

private let classificationColors: [CubeColor] = [.white, .red, .green, .yellow, .orange, .blue]

private func classificationMeasurement(
  _ l: Double, _ a: Double = 0, _ b: Double = 0, spread: Double = 1
) throws -> ColorMeasurement {
  try ColorMeasurement(
    median: LabColor(lightness: l, a: a, b: b),
    display: DisplaySRGB(red: l / 100, green: l / 100, blue: l / 100),
    spread: spread, sampleCount: 100)
}

private func classificationMetadata(_ slot: Face) throws -> CaptureMetadata {
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  return try CaptureMetadata(
    width: 300, height: 300, sourceOrientation: .up, sourceMirrored: false,
    corners: [
      ImagePoint(x: 0, y: 0), ImagePoint(x: 1, y: 0),
      ImagePoint(x: 1, y: 1), ImagePoint(x: 0, y: 1),
    ], pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]),
    samplingVersion: "test-v1")
}

private func completeClassificationDraft() throws -> ScanDraft {
  var draft = ScanDraft()
  for slot in ScanDraft.captureOrder {
    let center = 10 + Double(slot.rawValue) * 15
    var measurements = try (0..<9).map { _ in try classificationMeasurement(center) }
    if slot == .front { measurements[0] = try classificationMeasurement(25.5) }
    draft = try draft.accepting(
      ScanFace(
        slot: slot, measurements: measurements, metadata: classificationMetadata(slot),
        centerName: classificationColors[Int(slot.rawValue)]))
  }
  return draft
}

private let permissivePolicy = try! ScanPolicy(
  version: "fixture-v1", maximumSpread: 8, minimumMargin: 4,
  maximumDistance: 20, minimumCenterSeparation: 8)

@Test("R02/R03: classification waits for six confirmed centers")
func classificationRequiresCalibration() throws {
  var draft = ScanDraft()
  let values = Array(repeating: try classificationMeasurement(30), count: 9)
  draft = try draft.accepting(
    ScanFace(
      slot: .front, measurements: values, metadata: classificationMetadata(.front),
      centerName: .green))
  #expect(throws: ScanError.missingFace) { try draft.classify(using: permissivePolicy) }
}

@Test("R02/R03: nearest-center classification reports literal margin and canonical facelets")
func nearestCenterClassification() throws {
  let classification = try completeClassificationDraft().classify(using: permissivePolicy)
  #expect(classification.policyVersion == "fixture-v1")
  #expect(classification.stickers.count == 54)
  #expect(classification.stickers[18].color == .red)
  #expect(abs(classification.stickers[18].nearestDistance - 0.5) < 0.001)
  #expect(abs(classification.stickers[18].margin - 14) < 0.001)
  #expect(!classification.needsReview)
  let literal = try Facelets(
    notation: "UUUUUUUUURRRRRRRRRRFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB")
  #expect(try classification.canonicalFacelets() == literal)
}

@Test("R03: margin, distance and spread concerns block acceptance without forced recoloring")
func classificationConcerns() throws {
  let strict = try ScanPolicy(
    version: "strict", maximumSpread: 0.5, minimumMargin: 20,
    maximumDistance: 0.25, minimumCenterSeparation: 20)
  let result = try completeClassificationDraft().classify(using: strict)
  let sticker = result.stickers[18]
  #expect(sticker.color == .red)
  #expect(Set(sticker.concerns) == [.centersInseparable, .tooDistant, .lowMargin, .unstable])
  #expect(result.needsReview)
  #expect(throws: ScanError.invalidMeasurement) { try result.canonicalFacelets() }
}

@Test("R03: manual overrides survive center-dependent reclassification")
func classificationManualOverride() throws {
  let draft = try completeClassificationDraft()
    .setting(face: .front, row: 0, column: 0, color: .orange)
  let result = try draft.classify(
    using: try ScanPolicy(
      version: "strict", maximumSpread: 0, minimumMargin: 100,
      maximumDistance: 0, minimumCenterSeparation: 100))
  let sticker = result.stickers[18]
  #expect(sticker.color == .orange && sticker.source == .manual)
  #expect(sticker.concerns.isEmpty)
  #expect(result.needsReview)
}

@Test("R02: classification policy rejects non-finite values and empty versions")
func classificationPolicyGuards() throws {
  for value in [Double.nan, .infinity, -1] {
    #expect(throws: ScanError.invalidMeasurement) {
      try ScanPolicy(
        version: "v", maximumSpread: value, minimumMargin: 1,
        maximumDistance: 1, minimumCenterSeparation: 1)
    }
  }
  #expect(throws: ScanError.invalidMeasurement) {
    try ScanPolicy(
      version: "", maximumSpread: 1, minimumMargin: 1,
      maximumDistance: 1, minimumCenterSeparation: 1)
  }
  let malformed = Data(
    "{\"version\":\"\",\"maximumSpread\":1,\"minimumMargin\":1,\"maximumDistance\":1,\"minimumCenterSeparation\":1}"
      .utf8)
  #expect(throws: ScanError.invalidMeasurement) {
    try JSONDecoder().decode(ScanPolicy.self, from: malformed)
  }
}
