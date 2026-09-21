import Foundation

public enum ScanError: Error, Equatable {
  case invalidColor, invalidMeasurement, invalidCrop, invalidPose, invalidShape
  case unexpectedSlot, replacementRequired, missingFace, duplicateCenter
  case invalidCell, centerRequiresAssignment, revisionExhausted
}

/// Tagged display values, never canonical cube identity or camera YCbCr bytes.
public struct DisplaySRGB: Equatable, Sendable, Codable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public init(red: Double, green: Double, blue: Double) throws {
    guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw ScanError.invalidColor
    }
    self.red = red
    self.green = green
    self.blue = blue
  }
  private enum CodingKeys: String, CodingKey { case red, green, blue }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      red: values.decode(Double.self, forKey: .red),
      green: values.decode(Double.self, forKey: .green),
      blue: values.decode(Double.self, forKey: .blue))
  }
}

/// D65 CIELAB measurement. This is not a semantic color or confidence probability.
public struct LabColor: Equatable, Sendable, Codable {
  public let lightness: Double
  public let a: Double
  public let b: Double
  public init(lightness: Double, a: Double, b: Double) throws {
    guard lightness.isFinite, (0...100).contains(lightness), a.isFinite, b.isFinite else {
      throw ScanError.invalidColor
    }
    self.lightness = lightness
    self.a = a
    self.b = b
  }
  private enum CodingKeys: String, CodingKey { case lightness, a, b }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      lightness: values.decode(Double.self, forKey: .lightness),
      a: values.decode(Double.self, forKey: .a), b: values.decode(Double.self, forKey: .b))
  }
}

public struct ColorMeasurement: Equatable, Sendable, Codable {
  public let median: LabColor
  public let display: DisplaySRGB
  public let spread: Double
  public let sampleCount: Int
  public init(median: LabColor, display: DisplaySRGB, spread: Double, sampleCount: Int) throws {
    // Each normalized sticker contributes at most the specified 40×40 inner pixels.
    guard spread.isFinite, spread >= 0, (1...1600).contains(sampleCount) else {
      throw ScanError.invalidMeasurement
    }
    self.median = median
    self.display = display
    self.spread = spread
    self.sampleCount = sampleCount
  }
  private enum CodingKeys: String, CodingKey { case median, display, spread, sampleCount }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      median: values.decode(LabColor.self, forKey: .median),
      display: values.decode(DisplaySRGB.self, forKey: .display),
      spread: values.decode(Double.self, forKey: .spread),
      sampleCount: values.decode(Int.self, forKey: .sampleCount))
  }
}
