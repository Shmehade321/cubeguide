import Foundation

/// Maps the fixed square capture grid, drawn centered over an aspect-filled camera preview,
/// to normalized corners of the upright captured image with the same field of view.
public enum ViewfinderCrop {
  public struct Size: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
    }
  }

  /// Clockwise top-left, top-right, bottom-right, bottom-left, as `CaptureMetadata` expects.
  public static func corners(preview: Size, gridSide: Double, image: Size) throws -> [ImagePoint] {
    let values = [preview.width, preview.height, gridSide, image.width, image.height]
    guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
      gridSide <= min(preview.width, preview.height)
    else { throw ScanError.invalidCrop }
    // Aspect fill scales the image to cover the preview and centers it, hiding the overflow.
    let scale = max(preview.width / image.width, preview.height / image.height)
    let hiddenX = (image.width * scale - preview.width) / 2
    let hiddenY = (image.height * scale - preview.height) / 2
    let gridX = (preview.width - gridSide) / 2
    let gridY = (preview.height - gridSide) / 2
    // A grid touching the preview edge maps to 0 or 1 up to rounding; keep it in bounds.
    func unit(_ value: Double) -> Double {
      value < 0 && value > -1e-9 ? 0 : value > 1 && value < 1 + 1e-9 ? 1 : value
    }
    func point(_ x: Double, _ y: Double) throws -> ImagePoint {
      try ImagePoint(
        x: unit((x + hiddenX) / scale / image.width), y: unit((y + hiddenY) / scale / image.height))
    }
    return try [
      point(gridX, gridY), point(gridX + gridSide, gridY),
      point(gridX + gridSide, gridY + gridSide), point(gridX, gridY + gridSide),
    ]
  }
}
