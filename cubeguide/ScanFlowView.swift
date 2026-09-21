import CubeCore
import CubeScan
import CubeSession
import SwiftUI

struct ScanFlowView: View {
  @Bindable var controller: SessionController
  @Bindable var camera: CameraCapture
  @State private var choosingCenter = false
  @State private var choosingManualCenters = false
  @State private var editingSticker: StickerCell?

  private struct StickerCell: Hashable {
    let face: Face
    let index: Int
  }

  private static let reviewPolicy = try! ScanPolicy(
    version: "manual-review-required-v1", maximumSpread: 0,
    minimumMargin: .greatestFiniteMagnitude, maximumDistance: 0,
    minimumCenterSeparation: 0)

  private var workflow: ScanWorkflow? { controller.scanWorkflow }

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        switch workflow?.phase {
        case .scanning:
          Text("Scan the \(workflow?.target?.title ?? "next") face").font(.title.bold())
          Text("Keep the indicated face centered inside the square.")
          CameraPreview(session: camera.session)
            .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 2).padding(42) }
            .accessibilityHidden(true)
          Button("Capture face", systemImage: "camera.circle.fill") {
            let result = controller.sendScan(.capture)
            if result == .accepted {
              HapticFeedback.light(
                enabled: controller.preferences.haptics,
                effectsEnabled: controller.preferences.effects)
            } else if case .rejected = result {
              HapticFeedback.warning(
                enabled: controller.preferences.haptics,
                effectsEnabled: controller.preferences.effects)
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(!controller.isCameraReady)
          .accessibilityIdentifier("scan.capture")
        case .freezing:
          ProgressView("Freezing this face…")
        case .faceReview:
          Text("Review this face").font(.title.bold())
          if let image = camera.frozenImage {
            Image(uiImage: image).resizable().scaledToFit().clipShape(
              RoundedRectangle(cornerRadius: 16))
          }
          Text("Confirm the center color and compare all nine stickers with your cube.")
          Button(workflow?.review?.centerName?.title ?? "Choose center color") {
            choosingCenter = true
          }.accessibilityIdentifier("scan.center")
          Button("Use this face") { controller.sendScan(.accept) }
            .buttonStyle(.borderedProminent)
            .disabled(workflow?.review?.centerName == nil)
            .accessibilityIdentifier("scan.acceptFace")
          Button("Retake") { controller.sendScan(.retake) }
            .accessibilityIdentifier("scan.retake")
        case .saving:
          ProgressView("Saving scan…")
        case .storageError:
          Text("Couldn't save this scan").font(.title.bold())
          Button("Try again") { controller.sendScan(.retrySave) }
            .buttonStyle(.borderedProminent)
        case .pausedCapture:
          Text("Ready to continue scanning?").font(.title.bold())
          Text("Confirm that no cube layer has turned since the last accepted face.")
          Button("Continue with unchanged cube") {
            controller.sendScan(.resume(confirmedUnchanged: true))
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("scan.resume")
        case .editing:
          Text("Review all six faces").font(.title.bold())
          Text(
            "Automatic color confidence is not yet calibrated. Confirm every non-center sticker before accepting the scan."
          )
          ForEach(ScanDraft.captureOrder, id: \.rawValue) { face in
            scanFace(face)
          }
          if let classification {
            let remaining = classification.stickers.filter(\.needsReview).count
            Text(
              remaining == 0
                ? "All stickers have been reviewed." : "\(remaining) stickers still need review."
            )
            .foregroundStyle(remaining == 0 ? .green : .secondary)
            Button("Accept reviewed scan") {
              let result = controller.acceptReviewedScan(classification, confirmed: true)
              if case .rejected = result {
                HapticFeedback.warning(
                  enabled: controller.preferences.haptics,
                  effectsEnabled: controller.preferences.effects)
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(remaining != 0)
            .accessibilityIdentifier("scan.acceptReviewed")
          }
        default:
          ProgressView("Preparing camera…")
        }
        if controller.pendingScan != nil {
          Button("Enter colors manually") {
            if let palette = controller.pendingScan?.draft.confirmedCenters {
              controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
            } else {
              choosingManualCenters = true
            }
          }.accessibilityIdentifier("scan.manualFallback")
        }
        Button("Cancel scanning", role: .cancel) { controller.sendScan(.cancel) }
          .accessibilityIdentifier("scan.cancel")
      }
      .padding()
    }
    .confirmationDialog("Choose center color", isPresented: $choosingCenter) {
      ForEach(CubeColor.allCases, id: \.rawValue) { color in
        Button(color.title) { controller.sendScan(.editReview(.center(color))) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog(
      "Confirm sticker color",
      isPresented: Binding(
        get: { editingSticker != nil }, set: { if !$0 { editingSticker = nil } })
    ) {
      ForEach(CubeColor.allCases, id: \.rawValue) { color in
        Button(color.title) {
          if let cell = editingSticker {
            controller.sendScan(
              .correct(
                cell.face,
                .sticker(row: cell.index / 3, column: cell.index % 3, color: color)))
          }
          editingSticker = nil
        }
      }
      Button("Cancel", role: .cancel) { editingSticker = nil }
    }
    .sheet(isPresented: $choosingManualCenters) {
      NavigationStack {
        CenterAssignmentView(initial: controller.pendingScan?.draft.confirmedCenters) { palette in
          choosingManualCenters = false
          controller.switchScanToManual(confirmedCenters: palette, confirmed: true)
        }
        .navigationTitle("Manual entry")
      }
    }
  }

  private var classification: ScanClassification? {
    guard let draft = controller.pendingScan?.draft else { return nil }
    return try? draft.classify(using: Self.reviewPolicy)
  }

  @ViewBuilder
  private func scanFace(_ face: Face) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(face.title).font(.headline)
        Spacer()
        Button("Recapture") { controller.sendScan(.recapture(face)) }
          .accessibilityIdentifier("scan.recapture.\(face.code)")
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
        ForEach(0..<9, id: \.self) { index in
          let sticker = classification?.stickers[Int(face.rawValue) * 9 + index]
          Button {
            if index != 4 { editingSticker = StickerCell(face: face, index: index) }
          } label: {
            VStack(spacing: 3) {
              Text(sticker?.color.title ?? "Unknown")
                .font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
              if index == 4 {
                Text("Center").font(.caption2)
              } else {
                Text(sticker?.source == .manual ? "Confirmed" : "Review").font(.caption2)
              }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
          }
          .buttonStyle(.bordered)
          .disabled(index == 4)
          .accessibilityIdentifier("scan.sticker.\(face.code).\(index)")
        }
      }
    }
    .padding()
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }
}
