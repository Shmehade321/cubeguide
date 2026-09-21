import CubeCore
import CubeScan
import Testing
import UIKit

@testable import cubeguide

@MainActor
@Test("Camera processing normalizes, bounds, and samples an upright RGB image")
func cameraImageProcessorProducesBoundedFace() throws {
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format)
    .image { context in
      UIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
    }

  let result = try CameraImageProcessor.process(image, slot: .right)

  #expect(result.face.slot == .right)
  #expect(result.face.measurements.count == 9)
  #expect(result.face.metadata.width == 1920)
  #expect(result.face.metadata.height == 960)
  #expect(result.face.metadata.sourceOrientation == .up)
  #expect(result.face.metadata.sourceMirrored == false)
  #expect(result.face.metadata.pose.canonicalFace(at: .front) == .right)
  #expect(result.face.measurements.allSatisfy { $0.sampleCount == 64 })
  #expect(result.face.measurements.allSatisfy { $0.spread < 0.001 })
}
