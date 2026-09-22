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
  @Environment(\.dynamicTypeSize) private var textSize
  private var controlsLayout: AnyLayout {
    textSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
  }
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var showingAfter: Bool {
    comparisonAfter || controller.session.preview == .finished
      || (presentation.reduceMotion && presentation.staticPlayer?.showingAfter == true)
  }

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
          Text(showingAfter ? "Expected after this action" : presentation.previewDescription)
            .accessibilityIdentifier("guide.previewState")
          if presentation.reduceMotion, let palette = controller.palette {
            StaticGuideView(
              action: action, palette: palette, after: showingAfter,
              showColorLabels: controller.preferences.colorLabelsEnabled(
                differentiateWithoutColor: differentiate))
          } else if let scene = presentation.scene {
            GuideSceneSurface(
              model: scene,
              showColorLabels:
                controller.preferences.colorLabelsEnabled(differentiateWithoutColor: differentiate)
            )
            .frame(height: 220)
            .accessibilityLabel("Cube demonstration")
            .accessibilityIdentifier("guide.animatedCube")
            if let palette = controller.palette {
              GuideDirectionDiagram(action: action, palette: palette, after: showingAfter)
            }
          }
          Text(anchors(action)).font(.subheadline).multilineTextAlignment(.center)
          if [.preparingAction, .savingAcknowledgement].contains(controller.session.phase) {
            ProgressView("Saving your progress…")
          } else if [.resumeCheck, .storageError].contains(controller.session.phase) {
            Text(
              "Compare your physical cube before continuing. If a regrip was interrupted, return to the pictured holding position."
            )
            controlsLayout {
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
            controlsLayout {
              Button(controller.session.preview == .paused ? "Continue preview" : "Play") {
                controller.send(.play)
              }.accessibilityIdentifier("guide.play").disabled(
                controller.session.preview == .playing)
              Button("Pause") { controller.send(.pause) }
                .accessibilityIdentifier("guide.pause").disabled(
                  controller.session.preview != .playing)
              Button("Replay") { controller.send(.replay) }.accessibilityIdentifier("guide.replay")
            }
            Button(acknowledgement(action)) {
              let result = controller.send(.acknowledge(action.id))
              if result == .accepted {
                HapticFeedback.light(
                  enabled: controller.preferences.haptics,
                  effectsEnabled: controller.preferences.effects)
              } else {
                HapticFeedback.warning(
                  enabled: controller.preferences.haptics,
                  effectsEnabled: controller.preferences.effects)
              }
            }
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
      presentation.setReduceMotion(reduceMotion || CubeRendererPolicy.requiresStaticRenderer())
      presentation.refreshLabels(differentiateWithoutColor: differentiate)
      presentation.prepare()
    }
    .onChange(of: differentiate) { _, value in
      presentation.refreshLabels(differentiateWithoutColor: value)
    }
    .onChange(of: reduceMotion) { _, value in
      presentation.setReduceMotion(value || CubeRendererPolicy.requiresStaticRenderer())
    }
    .onChange(of: controller.session.phase) { _, _ in comparisonAfter = false }
    .onDisappear { presentation.stop() }
  }

  private func anchors(_ action: GuideAction) -> String {
    guard let palette = controller.palette else { return "" }
    let pose = showingAfter ? action.toPose : action.fromPose
    func color(_ face: Face) -> String {
      palette.colors[Int(pose.canonicalFace(at: face).rawValue)].title
    }
    return "Front: \(color(.front)) · Top: \(color(.up)) · Right: \(color(.right))"
  }
  private func acknowledgement(_ action: GuideAction) -> String {
    if case .regrip = action.operation { return "I'm holding it like this" }
    return "I did this move"
  }
  private func caption(_ action: GuideAction) -> String {
    PhraseCatalog.phrase(for: action.operation).caption
  }
}

/// SwiftUI updates must never reset the model's in-flight animation.
struct GuideSceneSurface: UIViewRepresentable {
  let model: CubeSceneModel
  let showColorLabels: Bool
  @Environment(\.colorScheme) private var colorScheme
  func makeUIView(context: Context) -> ARView { CubeSceneView.makeView(model: model) }
  func updateUIView(_ view: ARView, context: Context) {
    model.setColorLabels(showColorLabels)
    view.environment.background = .color(
      colorScheme == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.97, alpha: 1))
  }
  static func dismantleUIView(_ view: ARView, coordinator: ()) {
    view.scene.anchors.removeAll()
    view.isHidden = true
  }
}
