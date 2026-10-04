#if DEBUG && targetEnvironment(simulator)
  import CubeCore
  import CubeScan
  import Foundation
  import UIKit

  /// Simulator-only stand-in for the back camera, which simulators lack. When UI tests set
  /// CUBEGUIDE_SIMULATED_SCAN to 54 URFDLB facelet letters, each capture returns a photo of that
  /// cube's requested face drawn inside the on-screen grid, so the real capture, sampling,
  /// review and solve pipeline runs end to end. Nothing here is compiled into Release or
  /// physical-device builds.
  enum SimulatedCamera {
    nonisolated static let facelets: [Character]? = {
      guard let value = ProcessInfo.processInfo.environment["CUBEGUIDE_SIMULATED_SCAN"],
        value.count == 54
      else { return nil }
      return Array(value)
    }()

    nonisolated static var isActive: Bool { facelets != nil }

    /// Typical sticker colors of a standard scheme: Up white, Right red, Front green, Down
    /// yellow, Left orange, Back blue.
    nonisolated private static let stickers: [Character: (CGFloat, CGFloat, CGFloat)] = [
      "U": (0.93, 0.93, 0.93), "R": (0.78, 0.12, 0.18), "F": (0, 0.62, 0.32),
      "D": (1, 0.84, 0), "L": (1, 0.42, 0), "B": (0, 0.32, 0.73),
    ]

    nonisolated static func photo(of slot: Face, viewfinder: ViewfinderLayout?) -> Data? {
      guard let facelets else { return nil }
      let size = CGSize(width: 1440, height: 1920)
      let corners = CameraImageProcessor.corners(for: viewfinder, imageSize: size)
      guard corners.count == 4 else { return nil }
      let face = CGRect(
        x: corners[0].x * size.width, y: corners[0].y * size.height,
        width: (corners[1].x - corners[0].x) * size.width,
        height: (corners[3].y - corners[0].y) * size.height)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor(white: 0.35, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor(white: 0.05, alpha: 1).setFill()
        context.fill(face)
        let cell = face.width / 3
        for index in 0..<9 {
          let rgb = stickers[facelets[Int(slot.rawValue) * 9 + index]] ?? (0, 0, 0)
          UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
          context.fill(
            CGRect(
              x: face.minX + CGFloat(index % 3) * cell + cell * 0.06,
              y: face.minY + CGFloat(index / 3) * cell + cell * 0.06,
              width: cell * 0.88, height: cell * 0.88))
        }
      }
      return image.jpegData(compressionQuality: 0.95)
    }
  }
#endif
