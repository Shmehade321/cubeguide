/// Exact cubie lattice coordinates. Public values originate only from cube geometry.
public struct CubePosition: Equatable, Hashable, Sendable {
  public let x: Int
  public let y: Int
  public let z: Int

  public func isOnLayer(_ face: Face) -> Bool {
    let axis = CubeGeometry.axis(for: face)
    return x * axis.x + y * axis.y + z * axis.z == 1
  }

  public func viewed(at pose: CubeOrientation) -> CubePosition {
    let right = CubeGeometry.axis(for: pose.viewFace(for: .right))
    let up = CubeGeometry.axis(for: pose.viewFace(for: .up))
    let front = CubeGeometry.axis(for: pose.viewFace(for: .front))
    return CubePosition(
      x: x * right.x + y * up.x + z * front.x,
      y: x * right.y + y * up.y + z * front.y,
      z: x * right.z + y * up.z + z * front.z)
  }
}

/// A canonical sticker's cubie, outward direction and upward edge in the scene.
public struct CubeStickerPlacement: Equatable, Sendable {
  public let index: Int
  public let position: CubePosition
  public let normal: Face
  public let top: Face

  public func viewed(at pose: CubeOrientation) -> CubeStickerPlacement {
    CubeStickerPlacement(index: index, position: position.viewed(at: pose),
      normal: pose.viewFace(for: normal), top: pose.viewFace(for: top))
  }
}

/// Presentation geometry only; does not calculate puzzle state or acknowledgements.
public enum CubeGeometry {
  public static func axis(for face: Face) -> CubePosition {
    stickers[Int(face.rawValue) * 9 + 4].position
  }
  public static let cubies: [CubePosition] = (-1...1).flatMap { x in
    (-1...1).flatMap { y in
      (-1...1).compactMap { z in
        x == 0 && y == 0 && z == 0 ? nil : CubePosition(x: x, y: y, z: z)
      }
    }
  }
  public static let stickers: [CubeStickerPlacement] = Face.allCases.flatMap { face in
    (0..<9).map { cell in
      let row = cell / 3, column = cell % 3
      let position: CubePosition
      switch face {
      case .up: position = CubePosition(x: column - 1, y: 1, z: row - 1)
      case .right: position = CubePosition(x: 1, y: 1 - row, z: 1 - column)
      case .front: position = CubePosition(x: column - 1, y: 1 - row, z: 1)
      case .down: position = CubePosition(x: column - 1, y: -1, z: 1 - row)
      case .left: position = CubePosition(x: -1, y: 1 - row, z: column - 1)
      case .back: position = CubePosition(x: 1 - column, y: 1 - row, z: -1)
      }
      let top: Face = face == .up ? .back : face == .down ? .front : .up
      return CubeStickerPlacement(index: Int(face.rawValue) * 9 + cell,
        position: position, normal: face, top: top)
    }
  }
}
