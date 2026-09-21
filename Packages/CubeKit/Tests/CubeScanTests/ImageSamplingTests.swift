import CubeScan
import Testing

private func image(_ rows: [[(UInt8, UInt8, UInt8)]]) throws -> SRGBImage {
  try SRGBImage(
    width: rows[0].count, height: rows.count,
    bytes: rows.flatMap { $0.flatMap { [$0.0, $0.1, $0.2] } })
}

private let fullCrop = try! [
  ImagePoint(x: 0, y: 0), ImagePoint(x: 1, y: 0),
  ImagePoint(x: 1, y: 1), ImagePoint(x: 0, y: 1),
]

@Test("R02: source orientation and mirroring produce exact upright pixels")
func imageOrientation() throws {
  let source = try image([
    [(255, 0, 0), (0, 255, 0), (0, 0, 255)],
    [(0, 255, 255), (255, 0, 255), (255, 255, 0)],
  ])
  let right = try source.normalizedUpright(orientation: .right, mirrored: false)
  #expect(right.width == 2 && right.height == 3)
  #expect(
    right.bytes == [
      0, 255, 255, 255, 0, 0, 255, 0, 255, 0, 255, 0,
      255, 255, 0, 0, 0, 255,
    ])
  let mirrored = try source.normalizedUpright(orientation: .up, mirrored: true)
  #expect(
    mirrored.bytes == [
      0, 0, 255, 0, 255, 0, 255, 0, 0,
      255, 255, 0, 255, 0, 255, 0, 255, 255,
    ])
}

@Test("R02/R03: D65 conversion matches independent reference primaries")
func d65ReferenceColors() throws {
  let cases: [(DisplaySRGB, (Double, Double, Double))] = [
    (try DisplaySRGB(red: 1, green: 1, blue: 1), (100, 0, 0)),
    (try DisplaySRGB(red: 0, green: 0, blue: 0), (0, 0, 0)),
    (try DisplaySRGB(red: 1, green: 0, blue: 0), (53.2408, 80.0925, 67.2032)),
    (try DisplaySRGB(red: 0, green: 1, blue: 0), (87.7347, -86.1827, 83.1793)),
    (try DisplaySRGB(red: 0, green: 0, blue: 1), (32.2970, 79.1875, -107.8602)),
  ]
  for (input, expected) in cases {
    let actual = try ColorConversion.labD65(input)
    #expect(abs(actual.lightness - expected.0) < 0.02)
    #expect(abs(actual.a - expected.1) < 0.03)
    #expect(abs(actual.b - expected.2) < 0.03)
  }
}

@Test("R02/R03: homography sampling returns the literal nine sticker colors")
func samplesNineStickerGrid() throws {
  let colors: [(UInt8, UInt8, UInt8)] = [
    (255, 255, 255), (255, 255, 0), (255, 0, 0),
    (255, 128, 0), (0, 0, 255), (0, 255, 0),
    (64, 64, 64), (128, 128, 128), (192, 192, 192),
  ]
  var rows: [[(UInt8, UInt8, UInt8)]] = []
  for cellRow in 0..<3 {
    for _ in 0..<4 {
      rows.append(
        (0..<3).flatMap { cellColumn in
          Array(repeating: colors[cellRow * 3 + cellColumn], count: 4)
        })
    }
  }
  let result = try FaceImageSampler.measurements(
    in: image(rows), corners: fullCrop, samplesPerAxis: 4)
  #expect(result.count == 9)
  for (actual, color) in zip(result, colors) {
    #expect(abs(actual.display.red - Double(color.0) / 255) < 0.001)
    #expect(abs(actual.display.green - Double(color.1) / 255) < 0.001)
    #expect(abs(actual.display.blue - Double(color.2) / 255) < 0.001)
    #expect(actual.sampleCount == 16)
    #expect(actual.spread < 0.001)
  }
}

@Test("R02: sampling rejects invalid shapes and unbounded work")
func imageSamplingGuards() throws {
  #expect(throws: ScanError.invalidMeasurement) {
    try SRGBImage(width: 2, height: 2, bytes: [0, 0, 0])
  }
  let source = try image(
    Array(repeating: Array(repeating: (UInt8(0), UInt8(0), UInt8(0)), count: 3), count: 3))
  for count in [0, 41] {
    #expect(throws: ScanError.invalidMeasurement) {
      try FaceImageSampler.measurements(in: source, corners: fullCrop, samplesPerAxis: count)
    }
  }
  #expect(throws: ScanError.invalidCrop) {
    try FaceImageSampler.measurements(in: source, corners: Array(fullCrop.dropLast()))
  }
}
