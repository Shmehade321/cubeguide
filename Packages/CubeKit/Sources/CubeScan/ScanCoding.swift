import Foundation

extension KeyedDecodingContainer {
  func decodeFixed<T: Decodable>(
    _ type: T.Type, forKey key: Key, count: Int,
    invalid: ScanError = .invalidShape
  ) throws -> [T] {
    var container = try nestedUnkeyedContainer(forKey: key)
    var values: [T] = []
    while !container.isAtEnd {
      guard values.count < count else { throw invalid }
      values.append(try container.decode(T.self))
    }
    guard values.count == count else { throw invalid }
    return values
  }
}
