/// One consistent, validated store snapshot and the lease under which it was read.
public struct SessionRestoration: Equatable, Sendable {
  public let session: Session
  public let palette: CenterPalette?
  public let lease: StorageLease
}
