import Foundation
import Testing

@testable import cubeguide

@Test("R07: the affected iOS 18 runtime uses the safe renderer")
func rendererRuntimePolicy() {
  #expect(CubeRendererPolicy.requiresStaticRenderer(
    OperatingSystemVersion(majorVersion: 18, minorVersion: 5, patchVersion: 0)))
  #expect(!CubeRendererPolicy.requiresStaticRenderer(
    OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
}
