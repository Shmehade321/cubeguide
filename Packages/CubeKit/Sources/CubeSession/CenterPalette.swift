import CubeCore

public enum CubeColor: String, CaseIterable, Codable, Sendable {
  case white, yellow, red, orange, blue, green
}
public enum PaletteError: Error { case invalidCenters }

/// Explicit observed center names in canonical URFDLB order; no manufacturer defaults.
public struct CenterPalette: Equatable, Sendable, Codable {
  public let colors: [CubeColor]
  public init(_ colors: [CubeColor]) throws {
    guard colors.count == 6, Set(colors).count == 6 else { throw PaletteError.invalidCenters }
    self.colors = colors
  }
  private enum CodingKeys: String, CodingKey { case colors }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    var values = try container.nestedUnkeyedContainer(forKey: .colors)
    var colors: [CubeColor] = []
    while !values.isAtEnd {
      guard colors.count < 6 else { throw PaletteError.invalidCenters }
      colors.append(try values.decode(CubeColor.self))
    }
    try self.init(colors)
  }
}
