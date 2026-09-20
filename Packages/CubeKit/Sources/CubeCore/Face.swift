/// Canonical face identity, independent of a scanned sticker's display color.
public enum Face: UInt8, CaseIterable, Sendable, Codable {
    case up, right, front, down, left, back
}
