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
  // UIInterfaceOrientation.landscapeRight (home button right) is the back camera's native 0°.
  #expect(CaptureRotation.angle(for: .landscapeRight) == 0)
  #expect(CaptureRotation.angle(for: .landscapeLeft) == 180)
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

@MainActor
@Test("Camera processing records the true source orientation and mirroring")
func cameraImageProcessorRecordsSourceOrientation() throws {
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  let base = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 2400), format: format)
    .image { context in
      UIColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1200, height: 2400))
    }
  let cgImage = try #require(base.cgImage)
  let cases: [(UIImage.Orientation, FrameOrientation, Bool)] = [
    (.up, .up, false),
    (.upMirrored, .up, true),
    (.down, .down, false),
    (.downMirrored, .down, true),
    (.left, .left, false),
    (.leftMirrored, .left, true),
    (.right, .right, false),
    (.rightMirrored, .right, true),
  ]
  for (orientation, expected, expectedMirrored) in cases {
    let source = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    let result = try CameraImageProcessor.process(source, slot: .front)
    #expect(result.face.measurements.count == 9)
    #expect(result.face.metadata.sourceOrientation == expected)
    #expect(result.face.metadata.sourceMirrored == expectedMirrored)
  }
}

@MainActor
@Test("Camera processing keeps the photo's top row and left column as sticker row 0 and column 0")
func cameraImageProcessorPreservesImageOrientation() throws {
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  // Distinct bands: red encodes the image row, green encodes the image column.
  let levels: [CGFloat] = [0.9, 0.5, 0.1]
  let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900), format: format)
    .image { context in
      for row in 0..<3 {
        for column in 0..<3 {
          UIColor(red: levels[row], green: levels[column], blue: 0.3, alpha: 1).setFill()
          context.fill(CGRect(x: column * 300, y: row * 300, width: 300, height: 300))
        }
      }
    }
  let measurements = try CameraImageProcessor.process(image, slot: .front).face.measurements
  for row in 0..<3 {
    for column in 0..<3 {
      let display = measurements[row * 3 + column].display
      #expect(abs(display.red - Double(levels[row])) < 0.08, "row \(row), column \(column)")
      #expect(abs(display.green - Double(levels[column])) < 0.08, "row \(row), column \(column)")
    }
  }
}

@MainActor
@Test("Camera default crop for a capture is the on-screen grid, square in image pixels")
func cameraViewfinderCrop() {
  let layout = ViewfinderLayout(preview: CGSize(width: 398, height: 360), gridSide: 276)
  let corners = CameraImageProcessor.corners(
    for: layout, imageSize: CGSize(width: 3024, height: 4032))
  #expect(corners.count == 4)
  let width = (corners[1].x - corners[0].x) * 3024
  let height = (corners[3].y - corners[0].y) * 4032
  #expect(abs(width - height) < 1e-6)
  #expect(
    CameraImageProcessor.corners(for: nil, imageSize: CGSize(width: 3024, height: 4032))
      == CameraImageProcessor.defaultCorners())
}

private let gridFraction = 0.75

/// A face filling the grid, with dark gaps between stickers unless `gaps` is false.
private func syntheticFrame(
  _ colors: [SIMD3<Float>], width: Int = 1440, height: Int = 1080, gaps: Bool = true,
  texture: @escaping (Int) -> Bool = { _ in false }
) -> (Int, Int) -> SIMD3<Float> {
  let side = gridFraction * Double(min(width, height))
  let origin = ((Double(width) - side) / 2, (Double(height) - side) / 2)
  return { x, y in
    let u = (Double(x) - origin.0) / side
    let v = (Double(y) - origin.1) / side
    guard (0..<1).contains(u), (0..<1).contains(v) else { return SIMD3(10, 10, 10) }
    let nearBorder = [u, v].contains { abs($0 * 3 - ($0 * 3).rounded()) < 0.04 }
    if gaps, nearBorder { return SIMD3(15, 15, 15) }
    let index = Int(v * 3) * 3 + Int(u * 3)
    return texture(index) && (x + y).isMultiple(of: 2) ? SIMD3(0, 0, 0) : colors[index]
  }
}

private func detect(_ frame: @escaping (Int, Int) -> SIMD3<Float>, width: Int = 1440, height: Int = 1080)
  -> [SIMD3<Float>]?
{
  FaceDetector.cells(
    width: width, height: height, side: gridFraction * Double(min(width, height)), pixel: frame)
}

private let scrambled: [SIMD3<Float>] = [
  [255, 255, 255], [200, 30, 40], [255, 210, 0], [200, 30, 40], [255, 255, 255],
  [0, 150, 70], [0, 70, 180], [255, 100, 0], [255, 255, 255],
]

@Test("Live detection finds a scrambled face and ignores a logo on the center")
func faceDetectorFindsScrambledFace() throws {
  let cells = try #require(detect(syntheticFrame(scrambled) { $0 == 4 }))
  #expect(FaceDetector.distance(cells[1], scrambled[1]) < 1)
  #expect(FaceDetector.distance(cells[6], scrambled[6]) < 1)
  #expect(detect(syntheticFrame(scrambled, width: 1080, height: 1440), width: 1080, height: 1440) != nil)
}

@Test("Live detection accepts a solved face, which has dark gaps but a single color")
func faceDetectorFindsSolvedFace() {
  #expect(detect(syntheticFrame(Array(repeating: SIMD3<Float>(0, 150, 70), count: 9))) != nil)
}

@Test("Live detection rejects walls, posters without gaps and unevenly colored cells")
func faceDetectorRejectsNonFaces() {
  let wall = Array(repeating: SIMD3<Float>(180, 170, 160), count: 9)
  #expect(detect(syntheticFrame(wall, gaps: false)) == nil)
  #expect(detect(syntheticFrame(scrambled, gaps: false)) == nil)
  #expect(detect(syntheticFrame(scrambled) { $0 == 2 }) == nil)
}

@Test("Live detection watches the same square the viewfinder draws")
func faceDetectorSideMatchesViewfinder() throws {
  let layout = ViewfinderLayout(preview: CGSize(width: 360, height: 360), gridSide: 276)
  // Portrait: the 1080-pixel short side spans the preview width.
  let portrait = try #require(
    FaceDetector.side(for: layout, landscape: false, bufferWidth: 1440, bufferHeight: 1080))
  #expect(abs(portrait - 1080 * 276 / 360) < 0.5)
}

@Test("Auto-capture fires once per steady, focused streak and never for the same face twice")
func faceSteadinessFiresOncePerStreak() {
  var steadiness = FaceSteadiness()
  let fired = (0...FaceSteadiness.requiredFrames).map { _ in
    steadiness.update(scrambled, focused: true)
  }
  #expect(fired == Array(repeating: false, count: FaceSteadiness.requiredFrames) + [true])
  let repeated = steadiness.update(scrambled, focused: true)
  let lost = steadiness.update(nil, focused: true)
  #expect(!repeated && !lost)
  var unfocused = FaceSteadiness()
  let unfocusedFired = (0...10).map { _ in unfocused.update(scrambled, focused: false) }
  #expect(!unfocusedFired.contains(true))
  #expect(FaceDetector.sameFace(scrambled, scrambled.map { $0 + 5 }))
  #expect(!FaceDetector.sameFace(scrambled, scrambled.reversed()))
}

@Test("Zoom keeps a cube that fills the grid beyond the lens's closest focus distance")
func cameraZoomRespectsMinimumFocus() {
  let zoom = CameraZoom.focusZoom(minimumFocusMillimeters: 200, horizontalFieldOfView: 73)
  #expect((2.5...3.5).contains(zoom))
  #expect(CameraZoom.focusZoom(minimumFocusMillimeters: -1, horizontalFieldOfView: 73) == 1)
  #expect(CameraZoom.focusZoom(minimumFocusMillimeters: 20, horizontalFieldOfView: 73) == 1)
}
