import Foundation

enum CubeRendererPolicy {
  /// RealityKit's non-AR ARView has a reproducible CoreRE teardown crash on iOS 18.5.
  /// iOS 18 uses the already-tested static before/after renderer; newer runtimes use 3D.
  nonisolated static func requiresStaticRenderer(
    _ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) -> Bool {
    version.majorVersion < 26
  }
}
