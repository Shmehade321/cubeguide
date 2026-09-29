import CubeScan
import Testing

@Test("R02/§6: the default crop is the on-screen grid mapped through the aspect-filled preview")
func viewfinderCropMatchesGrid() throws {
  // A 3:4 portrait photo shown aspect-filled in a 361×360 point preview with a centered
  // 277-point grid: the photo is scaled to the preview width and cropped top and bottom.
  let corners = try ViewfinderCrop.corners(
    preview: .init(width: 361, height: 360), gridSide: 277,
    image: .init(width: 1440, height: 1920))
  let scale = 361.0 / 1440
  let hiddenTop = (1920 * scale - 360) / 2
  let left = (361 - 277) / 2 / scale / 1440
  let top = ((360 - 277) / 2 + hiddenTop) / scale / 1920
  let right = (361 - (361 - 277) / 2.0) / scale / 1440
  let bottom = ((360 - (360 - 277) / 2.0) + hiddenTop) / scale / 1920
  let expected = [(left, top), (right, top), (right, bottom), (left, bottom)]
  #expect(corners.count == 4)
  for (corner, value) in zip(corners, expected) {
    #expect(abs(corner.x - value.0) < 1e-9 && abs(corner.y - value.1) < 1e-9)
  }
  // The grid is square on screen, so the crop is square in image pixels.
  #expect(abs((right - left) * 1440 - (bottom - top) * 1920) < 1e-6)
}

@Test("R02: a wide preview crops the photo's sides instead and stays square")
func viewfinderCropWidePreview() throws {
  let corners = try ViewfinderCrop.corners(
    preview: .init(width: 600, height: 360), gridSide: 276,
    image: .init(width: 1440, height: 1920))
  let width = (corners[1].x - corners[0].x) * 1440
  let height = (corners[3].y - corners[0].y) * 1920
  #expect(abs(width - height) < 1e-6)
  #expect(abs((corners[0].x + corners[1].x) / 2 - 0.5) < 1e-9)
  #expect(abs((corners[0].y + corners[3].y) / 2 - 0.5) < 1e-9)
}

@Test("R02: impossible viewfinder geometry is rejected rather than clamped into a crop")
func viewfinderCropRejectsInvalidGeometry() {
  #expect(throws: ScanError.invalidCrop) {
    try ViewfinderCrop.corners(
      preview: .init(width: 0, height: 360), gridSide: 100, image: .init(width: 1440, height: 1920))
  }
  #expect(throws: ScanError.invalidCrop) {
    try ViewfinderCrop.corners(
      preview: .init(width: 361, height: 360), gridSide: 400,
      image: .init(width: 1440, height: 1920))
  }
  #expect(throws: ScanError.invalidCrop) {
    try ViewfinderCrop.corners(
      preview: .init(width: 361, height: 360), gridSide: .nan,
      image: .init(width: 1440, height: 1920))
  }
}

@Test("R02: a grid touching the preview edge maps to the image edge despite rounding")
func viewfinderCropEdgeGrid() throws {
  // 312×360 over 1080×1920 computes the left edge as -9.1e-17 without clamping.
  for (preview, image) in [((312.0, 360.0), (1080.0, 1920.0)), ((300.0, 400.0), (3024.0, 4032.0))] {
    let corners = try ViewfinderCrop.corners(
      preview: .init(width: preview.0, height: preview.1), gridSide: min(preview.0, preview.1),
      image: .init(width: image.0, height: image.1))
    #expect(corners.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    #expect(abs(corners[1].x - 1) < 1e-9 && abs(corners[0].x) < 1e-9)
  }
}
