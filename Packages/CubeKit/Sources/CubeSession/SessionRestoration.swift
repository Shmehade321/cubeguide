/// One consistent, validated store snapshot and the lease under which it was read.
public struct SessionRestoration: Equatable, Sendable {
  public let session: Session
  public let palette: CenterPalette?
  public let lease: StorageLease
  public let pendingScan: PendingScan?
  init(
    session: Session, palette: CenterPalette?, lease: StorageLease, pendingScan: PendingScan? = nil
  ) {
    self.session = session
    self.palette = palette
    self.lease = lease
    self.pendingScan = pendingScan
  }
}
