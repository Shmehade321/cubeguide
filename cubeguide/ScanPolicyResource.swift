import CubeScan
import Foundation

enum ScanPolicyResource {
  nonisolated static func load(bundle: Bundle = .main) throws -> ScanPolicy {
    guard let url = bundle.url(forResource: "scan-policy", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode(ScanPolicy.self, from: Data(contentsOf: url))
  }
}
