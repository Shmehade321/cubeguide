import CubeCore
import Foundation

public enum FrameOrientation: String, Codable, Sendable { case up, right, down, left }

/// Coordinates in the unmirrored upright processing image, normalized to 0...1.
public struct ImagePoint: Equatable, Sendable, Codable {
  public let x: Double
  public let y: Double
  public init(x: Double, y: Double) throws {
    guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
      throw ScanError.invalidCrop
    }
    self.x = x
    self.y = y
  }
  private enum CodingKeys: String, CodingKey { case x, y }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      x: values.decode(Double.self, forKey: .x), y: values.decode(Double.self, forKey: .y))
  }
}

public struct CaptureMetadata: Equatable, Sendable, Codable {
  public let width: Int
  public let height: Int
  public let sourceOrientation: FrameOrientation
  public let sourceMirrored: Bool
  /// Clockwise top-left, top-right, bottom-right, bottom-left in the upright image.
  public let corners: [ImagePoint]
  public let pose: CubeOrientation
  public let samplingVersion: String
  public init(
    width: Int, height: Int, sourceOrientation: FrameOrientation,
    sourceMirrored: Bool, corners: [ImagePoint], pose: CubeOrientation,
    samplingVersion: String
  ) throws {
    guard (1...1920).contains(width), (1...1920).contains(height), corners.count == 4 else {
      throw ScanError.invalidCrop
    }
    // Numerical degeneracy guard in normalized coordinates, not a calibrated image-quality score.
    for index in 0..<4 {
      let a = corners[index]
      let b = corners[(index + 1) % 4]
      let c = corners[(index + 2) % 4]
      let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      guard cross > 1e-8 else { throw ScanError.invalidCrop }
    }
    guard !samplingVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      samplingVersion.utf8.count <= 64
    else { throw ScanError.invalidMeasurement }
    self.width = width
    self.height = height
    self.sourceOrientation = sourceOrientation
    self.sourceMirrored = sourceMirrored
    self.corners = corners
    self.pose = pose
    self.samplingVersion = samplingVersion
  }
  private enum CodingKeys: String, CodingKey {
    case width, height, sourceOrientation, sourceMirrored, corners, pose, samplingVersion
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      width: values.decode(Int.self, forKey: .width),
      height: values.decode(Int.self, forKey: .height),
      sourceOrientation: values.decode(FrameOrientation.self, forKey: .sourceOrientation),
      sourceMirrored: values.decode(Bool.self, forKey: .sourceMirrored),
      corners: values.decodeFixed(
        ImagePoint.self, forKey: .corners, count: 4, invalid: .invalidCrop),
      pose: values.decode(CubeOrientation.self, forKey: .pose),
      samplingVersion: values.decode(String.self, forKey: .samplingVersion))
  }
}
