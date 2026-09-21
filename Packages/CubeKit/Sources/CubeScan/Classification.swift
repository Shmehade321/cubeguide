import CubeCore
import Foundation

public struct ScanPolicy: Equatable, Sendable, Codable {
  public let version: String
  public let maximumSpread: Double
  public let minimumMargin: Double
  public let maximumDistance: Double
  public let minimumCenterSeparation: Double

  public init(
    version: String, maximumSpread: Double, minimumMargin: Double,
    maximumDistance: Double, minimumCenterSeparation: Double
  ) throws {
    guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      version.utf8.count <= 64,
      [maximumSpread, minimumMargin, maximumDistance, minimumCenterSeparation]
        .allSatisfy({ $0.isFinite && $0 >= 0 })
    else { throw ScanError.invalidMeasurement }
    self.version = version
    self.maximumSpread = maximumSpread
    self.minimumMargin = minimumMargin
    self.maximumDistance = maximumDistance
    self.minimumCenterSeparation = minimumCenterSeparation
  }

  private enum CodingKeys: String, CodingKey {
    case version, maximumSpread, minimumMargin, maximumDistance, minimumCenterSeparation
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      version: values.decode(String.self, forKey: .version),
      maximumSpread: values.decode(Double.self, forKey: .maximumSpread),
      minimumMargin: values.decode(Double.self, forKey: .minimumMargin),
      maximumDistance: values.decode(Double.self, forKey: .maximumDistance),
      minimumCenterSeparation: values.decode(Double.self, forKey: .minimumCenterSeparation))
  }
}

public enum ClassificationSource: String, Equatable, Sendable, Codable {
  case center, automatic, manual
}

public enum ClassificationConcern: String, Equatable, Sendable, Codable {
  case centersInseparable, tooDistant, lowMargin, unstable
}

public struct ClassifiedSticker: Equatable, Sendable, Codable {
  public let color: CubeColor
  public let source: ClassificationSource
  public let nearestDistance: Double
  public let margin: Double
  public let concerns: [ClassificationConcern]
  public var needsReview: Bool { !concerns.isEmpty }
}

public struct ScanClassification: Equatable, Sendable {
  public let stickers: [ClassifiedSticker]
  public let palette: CenterPalette
  public let revision: UInt64
  public let policyVersion: String
  public var needsReview: Bool { stickers.contains(where: \.needsReview) }

  public func canonicalFacelets() throws -> Facelets {
    guard stickers.count == 54, !needsReview else { throw ScanError.invalidMeasurement }
    let labels = Dictionary(uniqueKeysWithValues: zip(palette.colors, Face.allCases))
    return try Facelets(
      stickers.map { sticker in
        guard let face = labels[sticker.color] else { throw ScanError.invalidColor }
        return face
      })
  }
}

extension ScanDraft {
  public func classify(using policy: ScanPolicy) throws -> ScanClassification {
    guard let palette = confirmedCenters else { throw ScanError.missingFace }
    let completeFaces = try Face.allCases.map { face -> ScanFace in
      guard let value = faces[Int(face.rawValue)] else { throw ScanError.missingFace }
      return value
    }
    let centers = try completeFaces.map { face -> (color: CubeColor, lab: LabColor) in
      guard let color = face.centerName else { throw ScanError.missingFace }
      return (color, face.measurements[4].median)
    }
    var centersInseparable = false
    for first in 0..<centers.count {
      for second in (first + 1)..<centers.count
      where distance(centers[first].lab, centers[second].lab) < policy.minimumCenterSeparation {
        centersInseparable = true
      }
    }
    var stickers: [ClassifiedSticker] = []
    stickers.reserveCapacity(54)
    for face in completeFaces {
      for index in 0..<9 {
        if index == 4, let color = face.centerName {
          stickers.append(
            ClassifiedSticker(
              color: color, source: .center, nearestDistance: 0,
              margin: .greatestFiniteMagnitude, concerns: []))
          continue
        }
        if let color = face.manualOverrides[index] {
          stickers.append(
            ClassifiedSticker(
              color: color, source: .manual, nearestDistance: 0,
              margin: .greatestFiniteMagnitude, concerns: []))
          continue
        }
        let measurement = face.measurements[index]
        let measured: [(color: CubeColor, distance: Double)] = centers.map { center in
          (color: center.color, distance: distance(measurement.median, center.lab))
        }
        let ranked = measured.sorted {
          $0.distance == $1.distance
            ? $0.color.rawValue < $1.color.rawValue : $0.distance < $1.distance
        }
        let nearest = ranked[0]
        let margin = ranked[1].distance - nearest.distance
        var concerns: [ClassificationConcern] = []
        if centersInseparable { concerns.append(.centersInseparable) }
        if nearest.distance > policy.maximumDistance { concerns.append(.tooDistant) }
        if margin < policy.minimumMargin { concerns.append(.lowMargin) }
        if measurement.spread > policy.maximumSpread { concerns.append(.unstable) }
        stickers.append(
          ClassifiedSticker(
            color: nearest.color, source: .automatic, nearestDistance: nearest.distance,
            margin: margin, concerns: concerns))
      }
    }
    return ScanClassification(
      stickers: stickers, palette: palette, revision: revision, policyVersion: policy.version)
  }
}

private func distance(_ first: LabColor, _ second: LabColor) -> Double {
  hypot(
    hypot(first.lightness - second.lightness, first.a - second.a),
    first.b - second.b)
}
