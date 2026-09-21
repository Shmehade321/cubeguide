import CubeCore
import CubeScan
@testable import CubeSession
import RealityKit
import UIKit
import XCTest
@testable import cubeguide

/// Captures actual RealityKit output for review, not automatic visual approval.
final class CubeOverlayVisualTests: XCTestCase {
  /// Isolates rendered resource teardown from SwiftUI navigation and session work.
  @MainActor
  func testRepeatedRenderedSceneTeardown() async throws {
    let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
    let draft = try ManualDraft(palette: palette).setting(face: .up, row: 0, column: 0, color: .blue)
    let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    for cycle in 1...20 {
      let released = try await renderAndTearDown(draft, in: windowScene)
      XCTAssertNil(released.model, "Scene owner retained after cycle \(cycle)")
    }
  }

  @MainActor
  private final class ReleasedScene {
    weak var model: CubeSceneModel?
    init(_ model: CubeSceneModel) { self.model = model }
  }

  @MainActor
  private func renderAndTearDown(_ draft: ManualDraft, in windowScene: UIWindowScene) async throws -> ReleasedScene {
    let scene = CubeSceneModel(draft: draft)
    let released = ReleasedScene(scene)
    let view = CubeSceneView.makeView(model: scene)
    let controller = UIViewController()
    controller.view = view
    let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(x: 0, y: 0, width: 500, height: 500)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    view.frame = window.bounds
    view.environment.background = .color(.white)
    // The representable performs this initial update after creating its view.
    scene.display(draft: draft, pose: .identity, showColorLabels: true)
    defer {
      CubeSceneView.dismantleUIView(view, coordinator: CubeSceneView.Coordinator(model: scene))
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKey()
    }
    // Artifact acquisition only; no performance or timing assertion.
    try await Task.sleep(for: .milliseconds(200))
    let captured = await withCheckedContinuation { continuation in
      view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
    }
    try requireRenderedContent(XCTUnwrap(captured))
    return released
  }

  @MainActor
  func testRenderedOverlayCatalog() async throws {
    let draft = try PracticeExample.draft()
    let state = try draft.canonicalFacelets()
    let scene = CubeSceneModel(draft: draft)
    let view = CubeSceneView.makeView(model: scene)
    let controller = UIViewController()
    controller.view = view
    let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(x: 0, y: 0, width: 500, height: 500)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    view.frame = window.bounds
    defer {
      scene.root.removeFromParent()
      view.scene.anchors.removeAll()
      window.isHidden = true
      window.rootViewController = nil
    }
    let fixtures: [(String, GuideOperation)] = [
      ("N01", .turn(Move(face: .front, turns: .clockwise))),
      ("N02", .turn(Move(face: .front, turns: .counterclockwise))),
      ("N03", .turn(Move(face: .front, turns: .half))),
      ("N04", .regrip(.yawLeft)), ("N05", .regrip(.yawRight)),
      ("N06", .regrip(.topToward)), ("N07", .regrip(.bottomToward)),
      ("N08", .regrip(.rollClockwise)), ("N09", .regrip(.rollCounterclockwise)),
    ]
    for (name, operation) in fixtures {
      let action: GuideAction
      switch operation {
      case .turn(let move):
        action = try XCTUnwrap(GuidePlanner.actions(for: move, at: .identity,
          state: state, sessionRevision: 1, moveIndex: 0).last)
      case .regrip(let regrip):
        action = GuideAction(id: try ActionID(sessionRevision: 1, moveIndex: 0, actionIndex: 0),
          operation: operation, before: state, after: state, fromPose: .identity,
          toPose: .identity.regripped(regrip))
      }
      for dark in [false, true] {
        view.overrideUserInterfaceStyle = dark ? .dark : .light
        view.environment.background = .color(UIColor(white: dark ? 0.04 : 0.97, alpha: 1))
        scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
        for (phase, progress) in [("before", 0.0), ("mid", 0.5), ("after", 1.0)] {
          scene.samplePreview(progress: progress)
          // Allow presentation frames to render before asking RealityKit for
          // its image. This is artifact acquisition, not a timing assertion.
          try await Task.sleep(for: .milliseconds(200))
          let captured = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
          }
          let image = try XCTUnwrap(captured)
          try requireRenderedContent(image)
          let attachment = XCTAttachment(image: image)
          attachment.name = "\(name)-\(dark ? "dark" : "light")-\(phase)-overlay"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
      }
    }
  }
  @MainActor
  private func requireRenderedContent(_ image: UIImage) throws {
    let cgImage = try XCTUnwrap(image.cgImage)
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 64, height: 64,
        bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let colors = Set(stride(from: 0, to: pixels.count, by: 4).map {
      UInt32(pixels[$0]) << 16 | UInt32(pixels[$0 + 1]) << 8 | UInt32(pixels[$0 + 2])
    })
    XCTAssertGreaterThan(colors.count, 12, "Blank or unrendered cube capture cannot qualify visuals")
  }

}
