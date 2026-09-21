import CubeCore
import CubeScan
import CubeSession
import RealityKit
import SwiftUI

/// The session remains the only authority for physical progress and persistence.
struct GuideFlowView: View {
  let controller: SessionController
  let presentation: GuidePresentation
  @State private var comparisonAfter = false
  private var showingAfter: Bool { comparisonAfter || controller.session.preview == .finished }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text("Solution verified").font(.headline).accessibilityIdentifier("solve.verified")
        if let progress = controller.session.guideProgress {
          Text("\(progress.plan.moves.count) moves in the verified solution.")
            .font(.caption).accessibilityIdentifier("solve.moveCount")
          Text("Step \(progress.acknowledgedActions + 1) of \(progress.actions.count)")
            .accessibilityIdentifier("guide.progress")
        }
        if let action = controller.session.pendingAction {
          Text(caption(action)).font(.headline).multilineTextAlignment(.center)
          Text(comparisonAfter ? "Expected after this action" : presentation.previewDescription)
          if let scene = presentation.scene {
            GuideSceneSurface(model: scene).frame(height: 220)
              .accessibilityLabel("Cube demonstration")
          }
          Text(anchors(action)).font(.subheadline).multilineTextAlignment(.center)
          if [.preparingAction, .savingAcknowledgement].contains(controller.session.phase) {
            ProgressView("Saving your progress…")
          } else if [.resumeCheck, .storageError].contains(controller.session.phase) {
            Text("Compare your physical cube before continuing. If a regrip was interrupted, return to the pictured holding position.")
            HStack {
              Button("Show before") {
                comparisonAfter = false
                presentation.showComparison(after: false)
              }.accessibilityIdentifier("guide.showBefore")
              Button("Show expected after") {
                comparisonAfter = true
                presentation.showComparison(after: true)
              }.accessibilityIdentifier("guide.showAfter")
            }
            Button("Matches after") { controller.send(.compare(.after)) }
              .accessibilityIdentifier("guide.matchesAfter")
              .disabled(!controller.session.preparationDurable)
            Button("Matches before") { controller.send(.compare(.before)) }
              .accessibilityIdentifier("guide.matchesBefore")
            Button("Not sure—start again") { controller.send(.compare(.uncertain)) }
              .accessibilityIdentifier("guide.uncertain")
          } else if !controller.session.aligned {
            Text("Match the front and top colors before starting.")
            Button("I'm holding it like this") { controller.send(.confirmAlignment) }
              .accessibilityIdentifier("guide.align")
          } else {
            HStack {
              Button(controller.session.preview == .paused ? "Continue preview" : "Play") {
                controller.send(.play)
              }.accessibilityIdentifier("guide.play").disabled(controller.session.preview == .playing)
              Button("Pause") { controller.send(.pause) }
                .accessibilityIdentifier("guide.pause").disabled(controller.session.preview != .playing)
              Button("Replay") { controller.send(.replay) }.accessibilityIdentifier("guide.replay")
            }
            Button(acknowledgement(action)) { controller.send(.acknowledge(action.id)) }
              .buttonStyle(.borderedProminent).accessibilityIdentifier("guide.acknowledge")
              .disabled(controller.session.preview != .finished)
          }
        }
        if controller.session.phase == .guide {
          Button("My cube looks different") { controller.send(.mismatch) }
            .accessibilityIdentifier("guide.mismatch")
        }
      }.buttonStyle(.bordered).controlSize(.large).padding()
    }
    .task(id: controller.session.pendingAction?.id) {
      comparisonAfter = false
      presentation.prepare()
    }
    .onChange(of: controller.session.phase) { _, _ in comparisonAfter = false }
    .onDisappear { presentation.stop() }
  }

  private func anchors(_ action: GuideAction) -> String {
    guard let palette = controller.palette else { return "" }
    let pose = showingAfter ? action.toPose : action.fromPose
    func color(_ face: Face) -> String { palette.colors[Int(pose.canonicalFace(at: face).rawValue)].title }
    return "Front: \(color(.front)) · Top: \(color(.up)) · Right: \(color(.right))"
  }
  private func acknowledgement(_ action: GuideAction) -> String {
    if case .regrip = action.operation { return "I'm holding it like this" }
    return "I did this move"
  }
  private func caption(_ action: GuideAction) -> String {
    switch action.operation {
    case .turn(let move):
      switch move.turns {
      case .clockwise: "Turn the front face clockwise one quarter turn."
      case .counterclockwise: "Turn the front face counterclockwise one quarter turn."
      case .half: "Turn the front face halfway around."
      }
    case .regrip(let operation):
      switch operation {
      case .yawLeft: "Turn the whole cube to the left."
      case .yawRight: "Turn the whole cube to the right."
      case .topToward: "Bring the top face toward you."
      case .bottomToward: "Bring the bottom face toward you."
      case .rollClockwise: "Roll the whole cube clockwise."
      case .rollCounterclockwise: "Roll the whole cube counterclockwise."
      }
    }
  }
}

/// SwiftUI updates must never reset the model's in-flight animation.
struct GuideSceneSurface: UIViewRepresentable {
  let model: CubeSceneModel
  @Environment(\.colorScheme) private var colorScheme
  func makeUIView(context: Context) -> ARView { CubeSceneView.makeView(model: model) }
  func updateUIView(_ view: ARView, context: Context) {
    view.environment.background = .color(colorScheme == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.97, alpha: 1))
  }
  static func dismantleUIView(_ view: ARView, coordinator: ()) {
    view.scene.anchors.removeAll()
    view.isHidden = true
  }
}
