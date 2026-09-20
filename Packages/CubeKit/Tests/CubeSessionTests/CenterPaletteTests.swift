import Foundation
import Testing
import CubeCore
@testable import CubeSession

@Test func explicitCenterPalette() throws {
  let names: [CubeColor] = [.green, .white, .orange, .blue, .yellow, .red]
  let palette = try CenterPalette(names)
  #expect(palette.colors == names)
  #expect(throws: PaletteError.self) { try CenterPalette([]) }
  #expect(throws: PaletteError.self) { try CenterPalette(Array(names.prefix(5))) }
  #expect(throws: PaletteError.self) { try CenterPalette(names + [.white]) }
  #expect(throws: PaletteError.self) {
    try CenterPalette([.white, .white, .red, .orange, .blue, .green])
  }
}

@Test func paletteDecodeValidatesCenters() throws {
  let valid = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  #expect(try JSONDecoder().decode(CenterPalette.self, from: JSONEncoder().encode(valid)) == valid)
  for json in [#"{"colors":[]}"#, #"{"colors":["white","white","red","orange","blue","green"]}"#,
               #"{"colors":["white","yellow","red","orange","blue","purple"]}"#] {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(CenterPalette.self, from: Data(json.utf8))
    }
  }
}
