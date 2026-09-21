import QuartzCore
import Foundation

/// Main-run-loop presentation ticks. Owners stop explicitly on pause/exit/background.
@MainActor
final class DisplayLinkFrames: PreviewFrameSource {
  private var link: CADisplayLink?
  private var update: (@MainActor () -> Void)?

  func start(_ update: @escaping @MainActor () -> Void) {
    stop()
    self.update = update
    let target = Target(owner: self)
    let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  func stop() {
    link?.invalidate()
    link = nil
    update = nil
  }

  private final class Target: NSObject {
    weak var owner: DisplayLinkFrames?
    init(owner: DisplayLinkFrames) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
      guard let owner, owner.link === link else {
        // An orphaned run-loop link invalidates itself without retaining its owner.
        link.invalidate()
        return
      }
      owner.update?()
    }
  }
}
