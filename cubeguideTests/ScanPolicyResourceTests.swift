import Testing
import CubeScan

@testable import cubeguide

@Test("R02/R03: installed scan policy stays fail-closed until a camera corpus calibrates it")
func bundledScanPolicy() throws {
  let policy = try ScanPolicyResource.load()
  #expect(policy.version == "manual-review-required-v1")
  #expect(policy.maximumSpread == 0)
  #expect(policy.maximumDistance == 0)
  #expect(policy.minimumMargin == 1_000_000)
}
