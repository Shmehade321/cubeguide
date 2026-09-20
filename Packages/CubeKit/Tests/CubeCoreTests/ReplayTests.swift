import Foundation
import Testing
@testable import CubeCore

@Test("V06: replay accepts solved empty and independently specified inverse solution")
func verifiedReplay() throws {
    let solved = try CubeValidation.validate(.solved).get()
    let empty = try Replay.verify([], for: solved, resourceVersion: "fixture-v1").get()
    #expect(empty.moves.isEmpty)
    #expect(empty.original == .solved)
    #expect(empty.resourceVersion == "fixture-v1")
    #expect(empty.originalStateHash.count == 64)
    let scrambled = try CubeValidation.validate(Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")).get()
    let moves = try Move.parse("R'")
    let plan = try Replay.verify(moves, for: scrambled, resourceVersion: "fixture-v2").get()
    #expect(plan.moves == moves)
    #expect(plan.original == scrambled.facelets)
    #expect(plan.original.applying(plan.moves) == .solved)
    #expect(plan.originalStateHash != empty.originalStateHash)
    #expect(plan.resourceVersion == "fixture-v2")
}

@Test("V06: empty, wrong, overlong and malformed solutions never become plans")
func rejectedReplay() throws {
    let scrambled = try CubeValidation.validate(Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")).get()
    #expect(Replay.verify([], for: scrambled, resourceVersion: "v1") == .failure(.notSolved))
    #expect(Replay.verify(try Move.parse("R"), for: scrambled, resourceVersion: "v1") == .failure(.notSolved))
    let solved = try CubeValidation.validate(.solved).get()
    let overlong = Array(repeating: Move(face: .up, turns: .clockwise), count: 32)
    #expect(Replay.verify(overlong, for: solved, resourceVersion: "v1") == .failure(.moveLimit))
    #expect(throws: CubeInputError.self) { try Move.parse("F3") }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Move.self, from: Data(#"{"face":0,"turns":0}"#.utf8))
    }
}

@Test("V06: original-state hash matches independent SHA-256 fixture")
func originalHash() throws {
    let cube = try CubeValidation.validate(.solved).get()
    let plan = try Replay.verify([],for:cube,resourceVersion:"fixture-v1").get()
    // Computed independently using Python hashlib over the literal canonical solved string.
    #expect(plan.originalStateHash == "ef351d057e1375062c3ca5717eac39821674507639652b41f197267bcefd10e8")
}
