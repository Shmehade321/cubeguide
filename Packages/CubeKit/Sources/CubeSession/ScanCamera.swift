import CubeCore
import CubeScan

public enum ScanCameraEvent: Sendable {
  case ready
  case interrupted(ScanPauseReason)
}
public enum ScanCameraResult: Sendable {
  case captured(ScanFace)
  case failed(ScanPauseReason)
}

/// Camera adapters own at most one transient frozen frame. Stop cancels in-flight work;
/// a delivered review frame remains until discardFrame. Late work must not retain new images.
@MainActor
public protocol ScanCamera: AnyObject {
  func start(slot: Face, event: @escaping @MainActor @Sendable (ScanCameraEvent) -> Void)
  func freeze(
    id: ScanOperationID, slot: Face,
    completion: @escaping @MainActor @Sendable (ScanCameraResult) -> Void)
  func stop()
  func discardFrame()
}
