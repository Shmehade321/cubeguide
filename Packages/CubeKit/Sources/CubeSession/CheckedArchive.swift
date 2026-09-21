import CryptoKit
import Foundation

/// Shared envelope integrity; each payload decoder still validates its own semantic invariants.
enum CheckedArchive {
  static let maximumBytes = 256 * 1024
  private struct Envelope: Codable {
    let schema: Int
    let payload: Data
    let checksum: String
  }
  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func encode<T: Encodable>(_ payload: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(payload)
    let result = try encoder.encode(Envelope(schema: 1, payload: bytes, checksum: hash(bytes)))
    guard result.count <= maximumBytes else { throw ArchiveError.sizeLimit }
    return result
  }
  static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    guard data.count <= maximumBytes else { throw ArchiveError.sizeLimit }
    let decoder = JSONDecoder()
    let version = try decoder.decode(Version.self, from: data)
    guard version.schema == 1 else { throw ArchiveError.unsupportedVersion }
    let envelope = try decoder.decode(Envelope.self, from: data)
    guard envelope.checksum == hash(envelope.payload) else { throw ArchiveError.corrupt }
    return try decoder.decode(type, from: envelope.payload)
  }
  private struct Version: Decodable { let schema: Int }
}
