import CubeCore
@testable import CubeSession
import SwiftUI
import XCTest
@testable import cubeguide

/// Produces review artifacts; successful rendering does not approve their appearance.
final class StaticGuideVisualTests: XCTestCase {
  @MainActor
  func testRenderStaticDirectionCatalog() throws {
    let draft = try PracticeExample.draft(), state = try draft.canonicalFacelets()
    let fixtures: [(String, String, GuideOperation)] = [
      ("N01", "Turn the front face clockwise one quarter turn.", .turn(Move(face: .front, turns: .clockwise))),
      ("N02", "Turn the front face counterclockwise one quarter turn.", .turn(Move(face: .front, turns: .counterclockwise))),
      ("N03", "Turn the front face halfway around.", .turn(Move(face: .front, turns: .half))),
      ("N04", "Turn the whole cube to the left.", .regrip(.yawLeft)),
      ("N05", "Turn the whole cube to the right.", .regrip(.yawRight)),
      ("N06", "Bring the top face toward you.", .regrip(.topToward)),
      ("N07", "Bring the bottom face toward you.", .regrip(.bottomToward)),
      ("N08", "Roll the whole cube clockwise.", .regrip(.rollClockwise)),
      ("N09", "Roll the whole cube counterclockwise.", .regrip(.rollCounterclockwise)),
    ]
    for (name, caption, operation) in fixtures {
      let action: GuideAction
      switch operation {
      case .turn(let move):
        action = try XCTUnwrap(GuidePlanner.actions(for: move, at: .identity, state: state,
          sessionRevision: 1, moveIndex: 0).last)
      case .regrip(let regrip):
        action = GuideAction(id: try ActionID(sessionRevision: 1, moveIndex: 0, actionIndex: 0),
          operation: operation, before: state, after: state, fromPose: .identity,
          toPose: .identity.regripped(regrip))
      }
      for sizeClass in [UserInterfaceSizeClass.regular, .compact] {
       for scheme in [ColorScheme.light, .dark] {
        let sheet = VStack(spacing: 12) {
          Text(caption).font(.headline)
          HStack(spacing: 12) {
            StaticGuideView(action: action, palette: draft.palette, after: false, showColorLabels: true)
            StaticGuideView(action: action, palette: draft.palette, after: true, showColorLabels: true)
          }
        }
        .padding(16).frame(width: 750, height: sizeClass == .compact ? 320 : 380)
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .background(scheme == .dark ? Color.black : Color.white)
        .environment(\.colorScheme, scheme)
        .environment(\.verticalSizeClass, sizeClass)
        .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name)-\(scheme == .dark ? "dark" : "light")-\(sizeClass == .compact ? "compact-" : "")static-before-after"
        attachment.lifetime = .keepAlways
        add(attachment)
       }
      }
    }
  }
}
