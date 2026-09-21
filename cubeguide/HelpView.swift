import SwiftUI

private enum HelpTopic: String, CaseIterable, Identifiable {
  case manual, capture, turns, supported, privacy, licenses, about
  var id: String { rawValue }
  var title: String {
    switch self {
    case .manual: "Enter and review colors"
    case .capture: "Show all six faces"
    case .turns: "How to hold and turn"
    case .supported: "Supported cubes"
    case .privacy: "Offline privacy"
    case .licenses: "Licenses"
    case .about: "About"
    }
  }
  var heading: String {
    switch self {
    case .manual: "Match your physical cube"
    case .capture: "Keep the sticker arrangement unchanged"
    case .turns: "Face turns and whole-cube turns"
    case .supported: "Standard six-color 3×3 cubes"
    case .privacy: "Your cube stays on this iPhone"
    case .licenses: "Included components"
    case .about: "About CubeGuide"
    }
  }
  var paragraphs: [String] {
    switch self {
    case .manual:
      [
        "Choose a Front face and a neighboring face for Up. Match all six center colors, using each color once. Do not assume a particular brand's color arrangement.",
        "Enter each remaining sticker. For each face, keep the neighbor named above its grid at the top. Choose face opens a focused view; Back to net returns to all six faces.",
        "Tap a sticker to change or clear it. Rotate 90° rotates that face's entered colors; it does not mean you should turn a layer of your physical cube.",
        "Validate checks the color counts and whether the entered pattern is possible. Review marked stickers and compare every face with your cube. A possible pattern can still differ from the cube in your hands.",
        "Your entered colors are solved describes your entries. Compare them with your physical cube before finishing.",
      ]
    case .capture:
      [
        "Use even light and keep the whole face visible. Avoid glare, deep shadows and fingers covering stickers.",
        "Show Front, Right, Back, Left, Up and Down. Turn the whole cube to show another face; do not twist a layer while recording faces.",
        "Check the named top neighbor on each face. Review all six faces against the cube before accepting the colors. If the cube's arrangement changed between sessions, start recording it again.",
      ]
    case .turns:
      [
        "A face turn moves one outer layer of nine stickers. Hold the rest of the cube still.",
        "Clockwise and counterclockwise are viewed looking straight at the face being turned, from outside the cube. A quarter turn is 90°; a half turn is 180°.",
        "A whole-cube turn changes how you hold the cube without twisting a layer. Keep the sticker arrangement unchanged.",
        "An animation is a demonstration. It does not prove you made the physical move. Compare your cube with the expected view before confirming a move.",
      ]
    case .supported:
      [
        "Use a standard fixed-center 3×3 cube with white, yellow, red, orange, blue and green faces. Stickered and stickerless cubes are supported; center assignments are explicit.",
        "Other sizes, picture cubes, oriented-center cubes and unusual shapes are outside this app's scope. Damaged or incorrectly reassembled cubes may need physical repair that CubeGuide does not provide.",
      ]
    case .privacy:
      [
        "Your entered colors and saved solution are stored on this iPhone. CubeGuide does not send them to a server, require an account, or save images to Photos.",
        "Help and the solver's required resources are included with the app. An internet connection is not needed to read these pages or calculate a solution.",
        "Use Delete local data in Settings to remove your saved colors and guide and reset preferences. Confirm only when you want to discard that work.",
      ]
    case .licenses:
      [
        "The cube model, solver and generated solver tables were written for the CubeGuide project.",
        "The app uses Apple's system frameworks. Development-only reference solvers and validation tools are not included in the iPhone app.",
      ]
    case .about:
      [
        "CubeGuide helps you record a physical 3×3 cube and check a solution against the colors you entered.",
        "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable")",
      ]
    }
  }
}

struct HelpView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List(HelpTopic.allCases) { topic in
        NavigationLink {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              Text(topic.heading).font(.title.bold()).accessibilityAddTraits(.isHeader)
              ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
          }
          .navigationTitle(topic.title).navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { done } }
        } label: {
          Text(topic.title).frame(minHeight: 44)
        }
        .accessibilityIdentifier("help.topic.\(topic.rawValue)")
      }
      .navigationTitle("Help")
      .toolbar { ToolbarItem(placement: .confirmationAction) { done } }
    }
  }
  private var done: some View {
    Button("Done") { dismiss() }.accessibilityIdentifier("help.done")
  }
}
