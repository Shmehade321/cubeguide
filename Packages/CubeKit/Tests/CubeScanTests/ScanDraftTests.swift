import CubeCore
import CubeScan
import Foundation
import Testing

private func measurement(_ index: Int = 0) throws -> ColorMeasurement {
  try ColorMeasurement(
    median: LabColor(lightness: Double(index), a: -4, b: 9),
    display: DisplaySRGB(red: 0.1, green: 0.2, blue: 0.3), spread: 2.5, sampleCount: 900)
}

private func metadata(_ slot: Face = .front) throws -> CaptureMetadata {
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  return try CaptureMetadata(
    width: 1440, height: 1920, sourceOrientation: .right,
    sourceMirrored: false,
    corners: [
      ImagePoint(x: 0.1, y: 0.1), ImagePoint(x: 0.9, y: 0.1),
      ImagePoint(x: 0.9, y: 0.9), ImagePoint(x: 0.1, y: 0.9),
    ],
    pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]), samplingVersion: "fixture-v1"
  )
}

private func observed(_ slot: Face = .front, center: CubeColor? = nil) throws -> ScanFace {
  try ScanFace(
    slot: slot, measurements: (0..<9).map { try measurement($0) },
    metadata: metadata(slot), centerName: center)
}

private func changed<T: Encodable>(_ value: T, _ edit: (inout [String: Any]) throws -> Void) throws
  -> Data
{
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  try edit(&object)
  return try JSONSerialization.data(withJSONObject: object)
}

@Test(
  "R02/R03: six explicit slots follow capture order; centers remain provisional until all are named"
)
func scanCaptureOrder() throws {
  let colors: [CubeColor] = [.green, .white, .orange, .blue, .yellow, .red]
  var draft = ScanDraft(revision: 12)
  #expect(draft.acceptedCount == 0 && draft.confirmedCenters == nil)
  #expect(draft.faces == Array(repeating: nil, count: 6))
  for (index, slot) in ScanDraft.captureOrder.enumerated() {
    #expect(draft.nextSlot == slot)
    let old = draft
    draft = try draft.accepting(observed(slot, center: colors[Int(slot.rawValue)]))
    #expect(draft.revision == old.revision + 1)
    #expect(draft.acceptedCount == index + 1)
    #expect(old.faces[Int(slot.rawValue)] == nil)
    #expect(draft.faces[Int(slot.rawValue)]?.slot == slot)
    if index < 5 { #expect(draft.confirmedCenters == nil) }
  }
  #expect(draft.nextSlot == nil)
  #expect(draft.confirmedCenters?.colors == colors)
}

@Test(
  "R02: capture cannot skip or silently replace slots, and a failed change preserves accepted faces"
)
func scanSlotGuards() throws {
  let empty = ScanDraft()
  #expect(throws: ScanError.unexpectedSlot) { try empty.accepting(observed(.right)) }
  let draft = try empty.accepting(observed(.front, center: .orange))
  #expect(throws: ScanError.replacementRequired) { try draft.accepting(observed(.front)) }
  let replacement = try observed(.front, center: .green)
  let replaced = try draft.accepting(replacement, replacing: true)
  #expect(replaced.faces[2] == replacement)
  #expect(draft.faces[2]?.centerName == .orange)
  #expect(replaced.acceptedCount == 1 && replaced.revision == 2)
  #expect(throws: ScanError.duplicateCenter) {
    try draft.accepting(observed(.right, center: .orange))
  }
}

@Test(
  "R03: manual corrections are separate from measurements and centers; duplicate names are rejected"
)
func scanManualCorrections() throws {
  let draft = try ScanDraft().accepting(observed(.front, center: .orange))
    .accepting(observed(.right, center: .white))
  let corrected = try draft.setting(face: .front, row: 2, column: 1, color: .red)
  #expect(corrected.faces[2]?.manualOverrides[7] == .red)
  #expect(corrected.faces[2]?.measurements == draft.faces[2]?.measurements)
  #expect(corrected.faces[1] == draft.faces[1])
  #expect(corrected.revision == draft.revision + 1)
  #expect(try corrected.setting(face: .front, row: 2, column: 1, color: nil).faces == draft.faces)
  #expect(throws: ScanError.centerRequiresAssignment) {
    try draft.setting(face: .front, row: 1, column: 1, color: .red)
  }
  #expect(throws: ScanError.duplicateCenter) { try draft.assigningCenter(.white, to: .front) }
  #expect(try draft.assigningCenter(.red, to: .front).faces[2]?.centerName == .red)
  #expect(try draft.assigningCenter(nil, to: .front).faces[2]?.centerName == nil)
  #expect(throws: ScanError.missingFace) { try draft.assigningCenter(.red, to: .down) }
  #expect(throws: ScanError.missingFace) {
    try draft.setting(face: .up, row: 0, column: 0, color: .red)
  }
  for (row, column) in [(-1, 0), (3, 0), (0, -1), (0, 3), (Int.max, 0)] {
    #expect(throws: ScanError.invalidCell) {
      try draft.setting(face: .front, row: row, column: column, color: .red)
    }
  }
}

@Test(
  "R03: rotation corrects samples and overrides together, keeps capture metadata and changes no other face"
)
func scanRotation() throws {
  let draft = try ScanDraft().accepting(observed(.front, center: .orange))
    .accepting(observed(.right, center: .white))
    .setting(face: .front, row: 0, column: 1, color: .blue)
  let rotated = try draft.rotating(.front, by: .clockwise)
  let face = try #require(rotated.faces[2])
  #expect(face.measurements.map(\.median.lightness) == [6, 3, 0, 7, 4, 1, 8, 5, 2])
  #expect(face.manualOverrides[5] == .blue && face.manualOverrides[1] == nil)
  #expect(face.centerName == .orange && face.correctionTurns == 1)
  #expect(face.metadata == draft.faces[2]?.metadata)
  #expect(rotated.faces[1] == draft.faces[1] && rotated.revision == draft.revision + 1)
  #expect(try rotated.rotating(.front, by: .counterclockwise).faces == draft.faces)
  #expect(
    try draft.rotating(.front, by: .half).faces == rotated.rotating(.front, by: .clockwise).faces)
  #expect(throws: ScanError.missingFace) { try draft.rotating(.back, by: .half) }
}

@Test("R18: scan revisions never wrap for capture, correction, center assignment or rotation")
func scanRevisionBounds() throws {
  #expect(throws: ScanError.revisionExhausted) {
    try ScanDraft(revision: .max).accepting(observed())
  }
  let bytes = try changed(ScanDraft().accepting(observed())) { $0["revision"] = UInt64.max }
  let final = try JSONDecoder().decode(ScanDraft.self, from: bytes)
  #expect(throws: ScanError.revisionExhausted) { try final.accepting(observed(), replacing: true) }
  #expect(throws: ScanError.revisionExhausted) {
    try final.setting(face: .front, row: 0, column: 0, color: .red)
  }
  #expect(throws: ScanError.revisionExhausted) { try final.assigningCenter(.red, to: .front) }
  #expect(throws: ScanError.revisionExhausted) { try final.rotating(.front, by: .clockwise) }
}

@Test("R03/R18: accepted scan data round-trips without durable image content")
func scanRoundTrip() throws {
  let draft = try ScanDraft(revision: 9).accepting(observed(.front, center: .orange))
    .setting(face: .front, row: 0, column: 0, color: .white).rotating(.front, by: .half)
  let bytes = try JSONEncoder().encode(draft)
  #expect(try JSONDecoder().decode(ScanDraft.self, from: bytes) == draft)
  let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  #expect(Set(object.keys) == ["faces", "revision"])
  let faces = try #require(object["faces"] as? [Any])
  let face = try #require(faces[2] as? [String: Any])
  #expect(
    Set(face.keys) == [
      "slot", "measurements", "manualOverrides", "centerName", "metadata", "correctionTurns",
    ])
}

@Test("R03: numeric color measurements reject non-finite and out-of-range data without clamping")
func scanNumericGuards() throws {
  for bad in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
    #expect(throws: ScanError.invalidColor) { try DisplaySRGB(red: bad, green: 0, blue: 1) }
    #expect(throws: ScanError.invalidColor) { try DisplaySRGB(red: 0, green: bad, blue: 1) }
    #expect(throws: ScanError.invalidColor) { try DisplaySRGB(red: 0, green: 0, blue: bad) }
  }
  for bad in [Double.nan, .infinity, -.infinity, -0.01, 100.01] {
    #expect(throws: ScanError.invalidColor) { try LabColor(lightness: bad, a: 0, b: 0) }
  }
  for bad in [Double.nan, .infinity, -.infinity] {
    #expect(throws: ScanError.invalidColor) { try LabColor(lightness: 50, a: bad, b: 0) }
    #expect(throws: ScanError.invalidColor) { try LabColor(lightness: 50, a: 0, b: bad) }
  }
  let sample = try measurement()
  for bad in [Double.nan, .infinity, -.infinity, -0.01] {
    #expect(throws: ScanError.invalidMeasurement) {
      try ColorMeasurement(
        median: sample.median, display: sample.display, spread: bad, sampleCount: 1)
    }
  }
  for count in [-1, 0, 1601, Int.max] {
    #expect(throws: ScanError.invalidMeasurement) {
      try ColorMeasurement(
        median: sample.median, display: sample.display, spread: 0, sampleCount: count)
    }
  }
  #expect(
    try ColorMeasurement(
      median: sample.median, display: sample.display, spread: 0, sampleCount: 1600
    ).sampleCount == 1600)
  #expect(throws: ScanError.invalidColor) {
    try JSONDecoder().decode(DisplaySRGB.self, from: changed(sample.display) { $0["red"] = 1.01 })
  }
  #expect(throws: ScanError.invalidColor) {
    try JSONDecoder().decode(LabColor.self, from: changed(sample.median) { $0["lightness"] = 101 })
  }
  #expect(throws: ScanError.invalidMeasurement) {
    try JSONDecoder().decode(ColorMeasurement.self, from: changed(sample) { $0["sampleCount"] = 0 })
  }
}

@Test(
  "R02/R03: crops require bounded upright coordinates, convex clockwise corners and tagged provenance"
)
func scanCropGuards() throws {
  let valid = try metadata()
  for bad in [Double.nan, .infinity, -0.01, 1.01] {
    #expect(throws: ScanError.invalidCrop) { try ImagePoint(x: bad, y: 0) }
    #expect(throws: ScanError.invalidCrop) { try ImagePoint(x: 0, y: bad) }
  }
  let malformed: [[[Double]]] = [
    [], [[0, 0], [1, 0], [1, 1]],
    [[0, 0], [1, 1], [1, 0], [0, 1]],  // crossed
    [[0, 0], [0, 1], [1, 1], [1, 0]],  // reversed
    [[0, 0], [1, 0], [1, 0], [0, 1]],  // repeated
    [[0, 0], [0.5, 0], [1, 0], [0, 1]],  // collinear
    [[0, 0], [1, 0], [1, 0.000000001], [0, 0.000000001]],  // numerically degenerate
    [[0, 0], [1, 0], [0.2, 0.2], [0, 1]],  // concave
  ]
  for corners in malformed {
    #expect(throws: ScanError.invalidCrop) {
      try CaptureMetadata(
        width: 640, height: 480, sourceOrientation: .up, sourceMirrored: false,
        corners: corners.map { try ImagePoint(x: $0[0], y: $0[1]) }, pose: .identity,
        samplingVersion: "v1")
    }
  }
  for (width, height) in [(0, 480), (640, -1), (1921, 1080), (640, Int.max)] {
    #expect(throws: ScanError.invalidCrop) {
      try CaptureMetadata(
        width: width, height: height, sourceOrientation: .up, sourceMirrored: false,
        corners: valid.corners, pose: .identity, samplingVersion: "v1")
    }
  }
  for version in ["", String(repeating: "a", count: 65)] {
    #expect(throws: ScanError.invalidMeasurement) {
      try CaptureMetadata(
        width: 640, height: 480, sourceOrientation: .up, sourceMirrored: false,
        corners: valid.corners, pose: .identity, samplingVersion: version)
    }
  }
  #expect(throws: ScanError.invalidCrop) {
    try JSONDecoder().decode(ImagePoint.self, from: changed(valid.corners[0]) { $0["x"] = -1 })
  }
  #expect(throws: ScanError.invalidCrop) {
    try JSONDecoder().decode(CaptureMetadata.self, from: changed(valid) { $0["width"] = 2000 })
  }
}

@Test("R02: face data validates nine cells and exact canonical front/top pose")
func scanFaceGuards() throws {
  let valid = try observed()
  for count in [0, 8, 10, 100] {
    #expect(throws: ScanError.invalidShape) {
      try ScanFace(
        slot: .front, measurements: Array(repeating: measurement(), count: count),
        metadata: metadata())
    }
    #expect(throws: ScanError.invalidShape) {
      try ScanFace(
        slot: .front, measurements: valid.measurements, metadata: metadata(),
        manualOverrides: Array(repeating: nil, count: count))
    }
  }
  for slot in Face.allCases {
    let captured = try metadata(slot)
    for pose in CubeOrientation.all {
      let candidate = try CaptureMetadata(
        width: captured.width, height: captured.height,
        sourceOrientation: captured.sourceOrientation, sourceMirrored: captured.sourceMirrored,
        corners: captured.corners, pose: pose, samplingVersion: captured.samplingVersion)
      if pose == captured.pose {
        #expect(
          try ScanFace(slot: slot, measurements: valid.measurements, metadata: candidate).slot
            == slot)
      } else {
        #expect(throws: ScanError.invalidPose) {
          try ScanFace(slot: slot, measurements: valid.measurements, metadata: candidate)
        }
      }
    }
  }
  var overrides = valid.manualOverrides
  overrides[4] = .red
  #expect(throws: ScanError.centerRequiresAssignment) {
    try ScanFace(
      slot: .front, measurements: valid.measurements, metadata: valid.metadata,
      manualOverrides: overrides)
  }
  #expect(throws: ScanError.invalidShape) {
    try ScanFace(
      slot: .front, measurements: valid.measurements, metadata: valid.metadata, correctionTurns: 4)
  }
}

@Test("R18: decoding rejects oversized, misplaced, duplicate-center and non-prefix scan records")
func scanDecodeGuards() throws {
  let draft = try ScanDraft().accepting(observed(.front, center: .orange))
    .accepting(observed(.right, center: .white))
  let edits: [(inout [String: Any]) throws -> Void] = [
    { $0["faces"] = Array(repeating: NSNull(), count: 7) },
    { $0["faces"] = [] },
    {
      var faces = try #require($0["faces"] as? [Any])
      faces.swapAt(1, 2)
      $0["faces"] = faces
    },
    {
      var faces = try #require($0["faces"] as? [Any])
      faces[2] = NSNull()
      $0["faces"] = faces
    },
    {
      var faces = try #require($0["faces"] as? [Any])
      var right = try #require(faces[1] as? [String: Any])
      right["centerName"] = "orange"
      faces[1] = right
      $0["faces"] = faces
    },
    {
      var faces = try #require($0["faces"] as? [Any])
      var front = try #require(faces[2] as? [String: Any])
      front["measurements"] = []
      faces[2] = front
      $0["faces"] = faces
    },
    {
      var faces = try #require($0["faces"] as? [Any])
      var front = try #require(faces[2] as? [String: Any])
      front["correctionTurns"] = 4
      faces[2] = front
      $0["faces"] = faces
    },
  ]
  for edit in edits {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(ScanDraft.self, from: changed(draft, edit))
    }
  }
}
