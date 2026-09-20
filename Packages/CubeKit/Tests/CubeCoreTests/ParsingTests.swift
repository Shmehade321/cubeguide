import Foundation
import Testing
@testable import CubeCore

private let solvedText = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

@Test("V01: parse exact facelets, preserve every position, round-trip bounded encoding")
func faceletRoundTrip() throws {
    let text = "URFDLBURFDLBURFDLBURFDLBURFDLBURFDLBURFDLBURFDLBURFDLB"
    let state = try Facelets(notation: text)
    #expect(state.notation == text)
    #expect(state.faces.count == 54)
    #expect(try JSONDecoder().decode(Facelets.self, from: JSONEncoder().encode(state)) == state)
    #expect(Facelets.solved.notation == solvedText)
}

@Test("V03: reject malformed facelet strings", arguments: ["", "U", String(repeating: "U", count: 53), String(repeating: "U", count: 55), String(repeating: "U", count: 53)+"X", String(repeating: "U", count: 53)+"🟦", String(repeating: "U", count: 54)+"\n"])
func malformedFacelets(text: String) {
    #expect(throws: CubeInputError.self) { try Facelets(notation: text) }
    #expect(throws: (any Error).self) { try JSONDecoder().decode(Facelets.self, from: JSONEncoder().encode(text)) }
}

@Test("V03: array constructor enforces exact sticker count", arguments: [0, 1, 53, 55, 1000])
func malformedArrays(count: Int) {
    #expect(throws: CubeInputError.self) { try Facelets(Array(repeating: .up, count: count)) }
}

@Test("V01: parse all move amounts and invert without changing face")
func moveNotation() throws {
    let moves = try Move.parse("U R2 F' D L2 B'")
    #expect(moves.map(\.face) == [.up, .right, .front, .down, .left, .back])
    #expect(moves.map(\.turns.rawValue) == [1, 2, 3, 1, 2, 3])
    #expect(moves.map(\.inverse.notation) == ["U'", "R2", "F", "D'", "L2", "B"])
    #expect(moves.map(\.inverse.inverse) == moves)
    #expect(try Move.parse("").isEmpty)
    #expect(try Move.parse("  R\nU'\tF2  ").map(\.notation) == ["R", "U'", "F2"])
}

@Test("V06: reject invalid or overlong move notation", arguments: ["X", "r", "R0", "R3", "R22", "R2'", "RU", "R’", String(repeating: "U ", count: 31), String(repeating: " ", count: 257)])
func malformedMoves(text: String) {
    #expect(throws: CubeInputError.self) { try Move.parse(text) }
}
