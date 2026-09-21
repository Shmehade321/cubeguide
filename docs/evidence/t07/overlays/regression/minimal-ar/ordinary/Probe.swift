import UIKit
import RealityKit
import Darwin

@MainActor
final class WeakView {
  weak var view: ARView?
  init(_ view: ARView) { self.view = view }
}

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    self.window = window
    Task { @MainActor in
      do {
        for cycle in 1...100 {
          let released = try await presentOne(window)
          try await Task.sleep(for: .milliseconds(100))
          guard released.view == nil else {
            NSLog("RealityKitProbe retained ARView after cycle %d", cycle)
            exit(3)
          }
          NSLog("RealityKitProbe presented and released cycle %d", cycle)
        }
        NSLog("RealityKitProbe completed all 100 verified cycles")
        exit(0)
      } catch {
        NSLog("RealityKitProbe diagnostic task failed: %@", String(describing: error))
        exit(2)
      }
    }
    return true
  }

  private func presentOne(_ window: UIWindow) async throws -> WeakView {
    let view = ARView(frame: window.bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
    let released = WeakView(view)
    let controller = UIViewController()
    controller.view = view
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      window.rootViewController = nil
      window.isHidden = true
    }
    try await Task.sleep(for: .milliseconds(200))
    guard view.window === window else {
      NSLog("RealityKitProbe ARView was not attached to the visible window")
      exit(4)
    }
    return released
  }
}
