import CryptoKit
import Foundation

public enum VerificationError: Error, Equatable, Sendable { case moveLimit, notSolved }
public struct VerifiedPlan: Equatable, Sendable {
    public let original: Facelets
    public let moves: [Move]
    public let originalStateHash: String
    public let resourceVersion: String
    fileprivate init(original: Facelets, moves: [Move], resourceVersion: String) {
        self.original = original; self.moves = moves; self.resourceVersion = resourceVersion
        originalStateHash = SHA256.hash(data: Data(original.notation.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
public enum Replay {
    public static func verify(_ moves: [Move], for cube: LegalCube, resourceVersion: String) -> Result<VerifiedPlan, VerificationError> {
        guard moves.count <= 30 else { return .failure(.moveLimit) }
        guard cube.facelets.applying(moves) == .solved else { return .failure(.notSolved) }
        return .success(VerifiedPlan(original: cube.facelets, moves: moves, resourceVersion: resourceVersion))
    }
}
