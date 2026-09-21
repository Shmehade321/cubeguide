import Foundation

public struct SRGBImage: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let bytes: [UInt8]

  public init(width: Int, height: Int, bytes: [UInt8]) throws {
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (byteCount, byteOverflow) = pixels.multipliedReportingOverflow(by: 3)
    guard width > 0, height > 0, width <= 1920, height <= 1920,
      !pixelOverflow, !byteOverflow, bytes.count == byteCount
    else { throw ScanError.invalidMeasurement }
    self.width = width
    self.height = height
    self.bytes = bytes
  }

  public func normalizedUpright(
    orientation: FrameOrientation, mirrored: Bool
  ) throws -> SRGBImage {
    let outputWidth = orientation == .right || orientation == .left ? height : width
    let outputHeight = orientation == .right || orientation == .left ? width : height
    var result = Array(repeating: UInt8.zero, count: bytes.count)
    for outputY in 0..<outputHeight {
      for outputX in 0..<outputWidth {
        let unmirroredX = mirrored ? outputWidth - 1 - outputX : outputX
        let source: (x: Int, y: Int)
        switch orientation {
        case .up: source = (unmirroredX, outputY)
        case .right: source = (outputY, height - 1 - unmirroredX)
        case .down: source = (width - 1 - unmirroredX, height - 1 - outputY)
        case .left: source = (width - 1 - outputY, unmirroredX)
        }
        let sourceOffset = (source.y * width + source.x) * 3
        let destinationOffset = (outputY * outputWidth + outputX) * 3
        result[destinationOffset..<(destinationOffset + 3)] =
          bytes[sourceOffset..<(sourceOffset + 3)]
      }
    }
    return try SRGBImage(width: outputWidth, height: outputHeight, bytes: result)
  }
}

public enum ColorConversion {
  public static func labD65(_ color: DisplaySRGB) throws -> LabColor {
    func linear(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let red = linear(color.red)
    let green = linear(color.green)
    let blue = linear(color.blue)
    let x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
    let y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
    let z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883
    func pivot(_ value: Double) -> Double {
      value > 216.0 / 24_389.0 ? pow(value, 1.0 / 3.0) : (24_389.0 / 27.0 * value + 16) / 116
    }
    let fx = pivot(x)
    let fy = pivot(y)
    let fz = pivot(z)
    return try LabColor(
      lightness: max(0, min(100, 116 * fy - 16)),
      a: 500 * (fx - fy), b: 200 * (fy - fz))
  }
}

public enum FaceImageSampler {
  public static func measurements(
    in image: SRGBImage, corners: [ImagePoint], samplesPerAxis: Int = 8
  ) throws -> [ColorMeasurement] {
    guard corners.count == 4 else { throw ScanError.invalidCrop }
    guard (1...40).contains(samplesPerAxis) else { throw ScanError.invalidMeasurement }
    // Reuse the crop contract so standalone sampling cannot accept crossed or degenerate input.
    _ = try CaptureMetadata(
      width: image.width, height: image.height, sourceOrientation: .up,
      sourceMirrored: false, corners: corners, pose: .identity,
      samplingVersion: "homography-srgb-d65-v1")
    let transform = try ProjectiveTransform(corners: corners)
    var result: [ColorMeasurement] = []
    result.reserveCapacity(9)
    for row in 0..<3 {
      for column in 0..<3 {
        var displays: [DisplaySRGB] = []
        var labs: [LabColor] = []
        displays.reserveCapacity(samplesPerAxis * samplesPerAxis)
        labs.reserveCapacity(samplesPerAxis * samplesPerAxis)
        for sampleY in 0..<samplesPerAxis {
          for sampleX in 0..<samplesPerAxis {
            let u = (Double(column) + (Double(sampleX) + 0.5) / Double(samplesPerAxis)) / 3
            let v = (Double(row) + (Double(sampleY) + 0.5) / Double(samplesPerAxis)) / 3
            let point = transform.map(x: u, y: v)
            guard point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y)
            else { continue }
            let x = min(image.width - 1, Int(point.x * Double(image.width)))
            let y = min(image.height - 1, Int(point.y * Double(image.height)))
            let offset = (y * image.width + x) * 3
            let display = try DisplaySRGB(
              red: Double(image.bytes[offset]) / 255,
              green: Double(image.bytes[offset + 1]) / 255,
              blue: Double(image.bytes[offset + 2]) / 255)
            displays.append(display)
            labs.append(try ColorConversion.labD65(display))
          }
        }
        guard !displays.isEmpty else { throw ScanError.invalidMeasurement }
        let display = try DisplaySRGB(
          red: median(displays.map(\.red)), green: median(displays.map(\.green)),
          blue: median(displays.map(\.blue)))
        let lab = try LabColor(
          lightness: median(labs.map(\.lightness)), a: median(labs.map(\.a)),
          b: median(labs.map(\.b)))
        let distances = labs.map {
          hypot(hypot($0.lightness - lab.lightness, $0.a - lab.a), $0.b - lab.b)
        }
        result.append(
          try ColorMeasurement(
            median: lab, display: display, spread: median(distances), sampleCount: displays.count))
      }
    }
    return result
  }
}

private func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  return sorted.count.isMultiple(of: 2)
    ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

private struct ProjectiveTransform {
  let a: Double
  let b: Double
  let c: Double
  let d: Double
  let e: Double
  let f: Double
  let g: Double
  let h: Double

  init(corners: [ImagePoint]) throws {
    guard corners.count == 4 else { throw ScanError.invalidCrop }
    let p0 = corners[0]
    let p1 = corners[1]
    let p2 = corners[2]
    let p3 = corners[3]
    let dx1 = p1.x - p2.x
    let dx2 = p3.x - p2.x
    let dy1 = p1.y - p2.y
    let dy2 = p3.y - p2.y
    let sx = p0.x - p1.x + p2.x - p3.x
    let sy = p0.y - p1.y + p2.y - p3.y
    let denominator = dx1 * dy2 - dx2 * dy1
    guard denominator.isFinite, abs(denominator) > 1e-12 else { throw ScanError.invalidCrop }
    g = (sx * dy2 - dx2 * sy) / denominator
    h = (dx1 * sy - sx * dy1) / denominator
    a = p1.x - p0.x + g * p1.x
    b = p3.x - p0.x + h * p3.x
    c = p0.x
    d = p1.y - p0.y + g * p1.y
    e = p3.y - p0.y + h * p3.y
    f = p0.y
  }

  func map(x: Double, y: Double) -> (x: Double, y: Double) {
    let denominator = g * x + h * y + 1
    return ((a * x + b * y + c) / denominator, (d * x + e * y + f) / denominator)
  }
}
