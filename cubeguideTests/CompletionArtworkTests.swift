import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI
import Testing
import XCTest
@testable import cubeguide

extension PresentationTests {
  @MainActor
  struct CompletionSceneTests {
    @Test("A07: final display removes a pending preview and retains palette and acknowledged pose")
    func finalState() throws {
      let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
      let draft = try PracticeExample.draft()
      let action = try #require(GuidePlanner.actions(for: Move(face: .front, turns: .clockwise),
        at: .identity, state: draft.canonicalFacelets(), sessionRevision: 1, moveIndex: 0).last)
      let scene = CubeSceneModel(draft: draft)
      scene.beginPreview(action, palette: draft.palette, showColorLabels: true)
      scene.samplePreview(progress: 0.4)
      let solved = try Facelets(notation: "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB")
      let pose = CubeOrientation.identity.regripped(.yawLeft)
      scene.display(state: solved, palette: palette, pose: pose, labels: true)
      #expect(scene.root.children.count == 26)
      #expect(scene.stickers.count == 54)
      for (point, body) in scene.bodies {
        let expected = point.viewed(at: pose)
        #expect(body.position == SIMD3(Float(expected.x), Float(expected.y), Float(expected.z)))
        #expect(body.children.allSatisfy { $0.name.hasPrefix("sticker.") })
      }
      for face in 0..<6 {
        let expected = ["G", "W", "O", "B", "Y", "R"][face]
        for index in face * 9..<face * 9 + 9 {
          #expect(scene.stickers[index]?.children.first?.name == "label.\(expected)")
        }
      }
      let transforms = scene.bodies.mapValues { $0.transform }
      scene.samplePreview(progress: 0.9)
      #expect(scene.bodies.mapValues { $0.transform } == transforms)
      scene.display(state: solved, palette: palette, pose: pose, labels: false)
      #expect(scene.stickers.values.allSatisfy { $0.children.isEmpty })
    }
  }
}

final class CompletionArtworkVisualTests: XCTestCase {
  @MainActor
  func testRenderedCompletionAppearance() async throws {
    XCTAssertFalse(UIAccessibility.isReduceMotionEnabled)
    let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
    let solved = try Facelets(notation: "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB")
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first { $0.isKeyWindow }
    let window = UIWindow(windowScene: scene)
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKeyAndVisible()
    }
    for scheme in [ColorScheme.light, .dark] {
      let artwork = CompletionArtwork(state: solved, palette: palette,
        pose: .identity.regripped(.yawLeft), showColorLabels: true)
        .padding().environment(\.colorScheme, scheme)
      let host = UIHostingController(rootView: artwork)
      host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
      window.rootViewController = host
      window.makeKeyAndVisible()
      try await Task.sleep(for: .seconds(1))
      host.view.layoutIfNeeded()
      func renderedView(in view: UIView) -> ARView? {
        if let rendered = view as? ARView { return rendered }
        return view.subviews.lazy.compactMap { renderedView(in: $0) }.first
      }
      let rendered = try XCTUnwrap(renderedView(in: host.view))
      XCTAssertEqual(rendered.scene.anchors.count, 1)
      let image: UIImage? = await withCheckedContinuation { continuation in
        rendered.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
      }
      let attachment = XCTAttachment(image: try XCTUnwrap(image))
      attachment.name = "A07-rendered-\(scheme)-custom-palette-yaw-left"
      attachment.lifetime = .keepAlways
      add(attachment)
      window.rootViewController = nil
    }
  }

  @MainActor
  func testStaticCompletionAppearance() throws {
    let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
    let solved = try Facelets(notation: "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB")
    for scheme in [ColorScheme.light, .dark] {
      for labels in [false, true] {
        let art = StaticCompletionCube(state: solved, palette: palette,
          pose: .identity, showColorLabels: labels)
          .frame(height: 180).padding().frame(width: 320)
          .foregroundStyle(scheme == .dark ? Color.white : Color.black)
          .background(scheme == .dark ? Color.black : Color.white)
          .environment(\.colorScheme, scheme)
          .environment(\.dynamicTypeSize, .accessibility5)
        let renderer = ImageRenderer(content: art)
        renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "A07-static-\(scheme)-labels-\(labels)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }
}
