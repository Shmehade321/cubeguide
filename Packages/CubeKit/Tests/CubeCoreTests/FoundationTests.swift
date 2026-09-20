import Testing
import CubeCore

@Test("V01: canonical face identities round-trip through serialized indices")
func canonicalFaces() throws {
    let decoded = [0, 1, 2, 3, 4, 5].compactMap { Face(rawValue: UInt8($0)) }
    #expect(decoded == [.up, .right, .front, .down, .left, .back])
    #expect(Face(rawValue: 6) == nil)
    #expect(Face(rawValue: 255) == nil)
}
