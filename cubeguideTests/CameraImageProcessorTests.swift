import CubeCore
import CubeScan
import CubeSession
import Testing
import UIKit

@testable import cubeguide

@Test("Camera capture attempts accept one matching callback and reject stale callbacks")
@MainActor
func cameraCaptureAttemptGuardRejectsStaleCallbacks() throws {
  var guardState = CaptureAttemptGuard()
  let workflow = UUID()
  let firstID = ScanOperationID(workflow: workflow, revision: 1, sequence: 1)
  let secondID = ScanOperationID(workflow: workflow, revision: 2, sequence: 2)

  let firstToken = guardState.begin(firstID)
  guardState.invalidate()
  let staleAfterInvalidation = guardState.complete(firstID, token: firstToken)
  #expect(!staleAfterInvalidation)

  let secondToken = guardState.begin(secondID)
  let wrongID = guardState.complete(firstID, token: secondToken)
  let accepted = guardState.complete(secondID, token: secondToken)
  let duplicate = guardState.complete(secondID, token: secondToken)
  #expect(!wrongID)
  #expect(accepted)
  #expect(!duplicate)
}

@Test("Camera capture maps every interface orientation to an explicit sensor rotation")
func cameraCaptureRotation() {
  #expect(CaptureRotation.angle(for: .portrait) == 90)
  #expect(CaptureRotation.angle(for: .portraitUpsideDown) == 270)
  #expect(CaptureRotation.angle(for: .landscapeLeft) == 0)
  #expect(CaptureRotation.angle(for: .landscapeRight) == 180)
  #expect(CaptureRotation.angle(for: .unknown) == 90)
}

@Test("Camera default crop is a complete bounded quadrilateral")
func cameraDefaultCrop() {
  let corners = CameraImageProcessor.defaultCorners()
  #expect(corners.count == 4)
  #expect(corners.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
}

@Test("Camera quality hints are advisory and identify dark flat frames")
@MainActor
func cameraQualityHints() {
  let assessment = CameraQuality.assess(Array(repeating: UInt8(2), count: 300))
  #expect(assessment.hints.contains { $0.contains("light") })
  #expect(assessment.hints.contains { $0.contains("edges") })
  #expect(assessment.hints.contains { $0.contains("steady") })
  #expect(CameraQuality.assess([0, 0, 0]).hints.count == 1)
}

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
  #expect(result.face.measurements.allSatisfy { $0.sampleCount == 1_600 })
  #expect(result.face.measurements.allSatisfy { $0.spread < 0.001 })
}
