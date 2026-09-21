import CubeCore
import Foundation

/// Accepted measurements only. A frozen image belongs to the camera adapter, never this value.
public struct ScanFace: Equatable, Sendable, Codable {
  public let slot: Face
  public let measurements: [ColorMeasurement]
  public let manualOverrides: [CubeColor?]
  public let centerName: CubeColor?
  public let metadata: CaptureMetadata
  public let correctionTurns: UInt8

  public init(
    slot: Face, measurements: [ColorMeasurement], metadata: CaptureMetadata,
    centerName: CubeColor? = nil, manualOverrides: [CubeColor?] = Array(repeating: nil, count: 9),
    correctionTurns: UInt8 = 0
  ) throws {
    guard measurements.count == 9, manualOverrides.count == 9, correctionTurns < 4 else {
      throw ScanError.invalidShape
    }
    guard manualOverrides[4] == nil else { throw ScanError.centerRequiresAssignment }
    let tops: [Face] = [.back, .up, .up, .front, .up, .up]
    guard metadata.pose.canonicalFace(at: .front) == slot,
      metadata.pose.canonicalFace(at: .up) == tops[Int(slot.rawValue)]
    else {
      throw ScanError.invalidPose
    }
    self.slot = slot
    self.measurements = measurements
    self.metadata = metadata
    self.centerName = centerName
    self.manualOverrides = manualOverrides
    self.correctionTurns = correctionTurns
  }
  public func setting(row: Int, column: Int, color: CubeColor?) throws -> ScanFace {
    guard (0..<3).contains(row), (0..<3).contains(column) else { throw ScanError.invalidCell }
    guard row != 1 || column != 1 else { throw ScanError.centerRequiresAssignment }
    var overrides = manualOverrides
    overrides[row * 3 + column] = color
    return try ScanFace(
      slot: slot, measurements: measurements, metadata: metadata,
      centerName: centerName, manualOverrides: overrides, correctionTurns: correctionTurns)
  }
  public func assigningCenter(_ color: CubeColor?) throws -> ScanFace {
    try ScanFace(
      slot: slot, measurements: measurements, metadata: metadata,
      centerName: color, manualOverrides: manualOverrides, correctionTurns: correctionTurns)
  }
  public func rotating(by turns: QuarterTurns) throws -> ScanFace {
    func rotate<T>(_ input: [T]) -> [T] {
      var result = input
      for _ in 0..<Int(turns.rawValue) {
        let previous = result
        for row in 0..<3 {
          for column in 0..<3 { result[column * 3 + 2 - row] = previous[row * 3 + column] }
        }
      }
      return result
    }
    return try ScanFace(
      slot: slot, measurements: rotate(measurements), metadata: metadata,
      centerName: centerName, manualOverrides: rotate(manualOverrides),
      correctionTurns: (correctionTurns + turns.rawValue) % 4)
  }
  private enum CodingKeys: String, CodingKey {
    case slot, measurements, manualOverrides, centerName, metadata, correctionTurns
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      slot: values.decode(Face.self, forKey: .slot),
      measurements: values.decodeFixed(ColorMeasurement.self, forKey: .measurements, count: 9),
      metadata: values.decode(CaptureMetadata.self, forKey: .metadata),
      centerName: values.decodeIfPresent(CubeColor.self, forKey: .centerName),
      manualOverrides: values.decodeFixed(CubeColor?.self, forKey: .manualOverrides, count: 9),
      correctionTurns: values.decode(UInt8.self, forKey: .correctionTurns))
  }
}

public struct ScanDraft: Equatable, Sendable, Codable {
  public static let captureOrder: [Face] = [.front, .right, .back, .left, .up, .down]
  /// Canonical URFDLB slots, independent of capture order.
  public let faces: [ScanFace?]
  public let revision: UInt64
  public var acceptedCount: Int { faces.compactMap { $0 }.count }
  public var nextSlot: Face? { Self.captureOrder.first { faces[Int($0.rawValue)] == nil } }
  public var confirmedCenters: CenterPalette? {
    let names = faces.compactMap { $0?.centerName }
    return try? CenterPalette(names)
  }
  public init(revision: UInt64 = 0) {
    faces = Array(repeating: nil, count: 6)
    self.revision = revision
  }
  private init(faces: [ScanFace?], revision: UInt64) throws {
    guard faces.count == 6 else { throw ScanError.invalidShape }
    var missing = false
    var names = Set<CubeColor>()
    for slot in Self.captureOrder {
      guard let face = faces[Int(slot.rawValue)] else {
        missing = true
        continue
      }
      guard !missing, face.slot == slot else { throw ScanError.invalidShape }
      if let name = face.centerName, !names.insert(name).inserted {
        throw ScanError.duplicateCenter
      }
    }
    self.faces = faces
    self.revision = revision
  }
  private func replacing(_ face: ScanFace) throws -> ScanDraft {
    let (revision, overflow) = revision.addingReportingOverflow(1)
    guard !overflow else { throw ScanError.revisionExhausted }
    var faces = faces
    faces[Int(face.slot.rawValue)] = face
    return try ScanDraft(faces: faces, revision: revision)
  }
  private func accepted(_ face: Face) throws -> ScanFace {
    guard let value = faces[Int(face.rawValue)] else { throw ScanError.missingFace }
    return value
  }
  public func accepting(_ face: ScanFace, replacing: Bool = false) throws -> ScanDraft {
    if faces[Int(face.slot.rawValue)] != nil {
      guard replacing else { throw ScanError.replacementRequired }
    } else {
      guard face.slot == nextSlot else { throw ScanError.unexpectedSlot }
    }
    return try self.replacing(face)
  }
  public func setting(face: Face, row: Int, column: Int, color: CubeColor?) throws -> ScanDraft {
    guard (0..<3).contains(row), (0..<3).contains(column) else { throw ScanError.invalidCell }
    guard row != 1 || column != 1 else { throw ScanError.centerRequiresAssignment }
    let value = try accepted(face)
    return try replacing(value.setting(row: row, column: column, color: color))
  }
  public func assigningCenter(_ color: CubeColor?, to face: Face) throws -> ScanDraft {
    let value = try accepted(face)
    return try replacing(value.assigningCenter(color))
  }
  public func rotating(_ face: Face, by turns: QuarterTurns) throws -> ScanDraft {
    let value = try accepted(face)
    return try replacing(value.rotating(by: turns))
  }
  private enum CodingKeys: String, CodingKey { case faces, revision }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      faces: values.decodeFixed(ScanFace?.self, forKey: .faces, count: 6),
      revision: values.decode(UInt64.self, forKey: .revision))
  }
}
