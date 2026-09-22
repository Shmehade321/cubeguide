import CubeCore
import CubeScan
import CubeSession
import SwiftUI
import UIKit

struct ScanFlowView: View {
  @Bindable var controller: SessionController
  @Bindable var camera: CameraCapture
  @State private var choosingCenter = false
  @State private var choosingManualCenters = false
  @State private var editingSticker: StickerCell?
  @State private var cropCorners = CameraImageProcessor.defaultCorners().map {
    CGPoint(x: $0.x, y: $0.y)
  }
  @State private var cropError: String?
  @State private var isReprocessing = false
  @State private var cropTask: Task<Void, Never>?
  @State private var previewTurns = 0
  @Environment(\.openURL) private var openURL

  private struct StickerCell: Hashable {
    let face: Face
    let index: Int
  }

  private static let reviewPolicy = try? ScanPolicyResource.load()

  private var workflow: ScanWorkflow? { controller.scanWorkflow }

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        switch workflow?.phase {
        case .scanning:
          Text("Scan the \(workflow?.target?.title ?? "next") face").font(.title.bold())
          captureProgress
          if let target = workflow?.target {
            Label("Keep \(target.topNeighbor.title) at the top", systemImage: "arrow.up")
              .font(.headline)
              .accessibilityIdentifier("scan.topNeighbor")
          }
          Text("Fit the whole face inside the grid. Avoid glare and hold still so every sticker is sharp.")
            .foregroundStyle(.secondary)
          CameraPreview(session: camera.session)
            .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { viewfinderGrid.padding(42) }
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
            CropEditor(image: image, corners: $cropCorners) { updateCrop() }
              .frame(minHeight: 300)
              .rotationEffect(.degrees(Double(previewTurns * 90)))
              .accessibilityIdentifier("scan.cropEditor")
          }
          Text("Drag the four handles to the face corners. Readings are provisional until all six centers are known.")
            .foregroundStyle(.secondary)
          if isReprocessing { ProgressView("Updating color readings…") }
          if let cropError {
            Label(cropError, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
          ForEach(camera.qualityHints, id: \.self) { hint in
            Label(hint, systemImage: "light.max")
              .foregroundStyle(.orange)
              .accessibilityIdentifier("scan.qualityHint")
          }
          faceReviewGrid
          Button(workflow?.review?.centerName?.title ?? "Choose center color") {
            choosingCenter = true
          }.accessibilityIdentifier("scan.center")
          Button("Rotate preview 90°", systemImage: "rotate.right") {
            if controller.sendScan(.editReview(.rotate(.clockwise))) == .accepted {
              previewTurns = (previewTurns + 1) % 4
            }
          }
          .accessibilityIdentifier("scan.rotatePreview")
          Button("Use this face") { controller.sendScan(.accept) }
            .buttonStyle(.borderedProminent)
            .disabled(workflow?.review?.centerName == nil || isReprocessing)
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
          if workflow?.pauseReason == .permissionDenied {
            Text("Camera access is off").font(.title.bold())
            Text("Allow camera access in Settings, or enter the cube colors manually.")
            Button("Open Settings", systemImage: "gear") {
              if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.openSettings")
          } else {
            Text("Scanning paused").font(.title.bold())
            Text(pauseExplanation)
            Button("Continue with unchanged cube") {
              controller.sendScan(.resume(confirmedUnchanged: true))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.resume")
          }
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
            if workflow?.phase == .faceReview {
              controller.sendScan(
                .editReview(
                  .sticker(row: cell.index / 3, column: cell.index % 3, color: color)))
            } else {
              controller.sendScan(
                .correct(
                  cell.face,
                  .sticker(row: cell.index / 3, column: cell.index % 3, color: color)))
            }
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
    .onChange(of: workflow?.review?.slot) { _, slot in
      guard slot != nil else { return }
      cropCorners = CameraImageProcessor.defaultCorners().map { CGPoint(x: $0.x, y: $0.y) }
      cropError = nil
      previewTurns = 0
    }
    .onDisappear { cropTask?.cancel() }
  }

  private var pauseExplanation: String {
    switch workflow?.pauseReason {
    case .thermal: "The phone needs to cool down. Keep every cube layer unchanged before continuing."
    case .orientationChanged: "The phone orientation changed during capture. Keep every cube layer unchanged before continuing."
    case .cameraUnavailable: "The camera stopped unexpectedly. Keep every cube layer unchanged before continuing."
    case .captureFailed, .invalidObservation: "That picture could not be read. Keep every cube layer unchanged and try again."
    default: "Confirm that no cube layer has turned since the last accepted face."
    }
  }

  private var captureProgress: some View {
    HStack(spacing: 8) {
      ForEach(Array(ScanDraft.captureOrder.enumerated()), id: \.element.rawValue) { index, face in
        VStack(spacing: 4) {
          Image(systemName: index < (controller.pendingScan?.draft.acceptedCount ?? 0) ? "checkmark.circle.fill" : "circle")
          Text(face.code).font(.caption.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(face == workflow?.target ? Color.accentColor : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          index < (controller.pendingScan?.draft.acceptedCount ?? 0)
            ? "\(face.title) captured" : face == workflow?.target
              ? "\(face.title), current face" : "\(face.title), not captured")
      }
    }
    .accessibilityIdentifier("scan.progress")
  }

  private var viewfinderGrid: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 3)
      HStack(spacing: 0) {
        Spacer(); Divider().overlay(.white); Spacer(); Divider().overlay(.white); Spacer()
      }
      VStack(spacing: 0) {
        Spacer(); Divider().overlay(.white); Spacer(); Divider().overlay(.white); Spacer()
      }
    }
  }

  private var faceReviewGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
      ForEach(0..<9, id: \.self) { index in
        let override = workflow?.review?.manualOverrides[index]
        let color = index == 4 ? workflow?.review?.centerName : override ?? provisionalColor(at: index)
        Button {
          guard let face = workflow?.review?.slot else { return }
          if index == 4 { choosingCenter = true } else { editingSticker = StickerCell(face: face, index: index) }
        } label: {
          VStack(spacing: 5) {
            Circle()
              .fill(measuredColor(at: index))
              .overlay(Circle().stroke(.primary.opacity(0.4), lineWidth: 1))
              .frame(width: 30, height: 30)
            Text(color?.title ?? "Unknown").font(.caption.bold()).lineLimit(1)
            Text(index == 4 ? "Center" : override == nil ? "Provisional" : "Confirmed")
              .font(.caption2).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(
          "Row \(index / 3 + 1), column \(index % 3 + 1), \(color?.title ?? "unknown"), tap to change")
        .accessibilityIdentifier("scan.reviewSticker.\(index)")
      }
    }
  }

  private func measuredColor(at index: Int) -> Color {
    guard let display = workflow?.review?.measurements[index].display else { return .gray }
    return Color(.sRGB, red: display.red, green: display.green, blue: display.blue, opacity: 1)
  }

  private func provisionalColor(at index: Int) -> CubeColor? {
    guard let measurement = workflow?.review?.measurements[index].median else { return nil }
    var centers: [(CubeColor, LabColor)] = controller.pendingScan?.draft.faces.compactMap { face in
      guard let face, let color = face.centerName else { return nil }
      return (color, face.measurements[4].median)
    } ?? []
    if let review = workflow?.review, let color = review.centerName {
      centers.removeAll { $0.0 == color }
      centers.append((color, review.measurements[4].median))
    }
    return centers.min {
      labDistance(measurement, $0.1) < labDistance(measurement, $1.1)
    }?.0
  }

  private func labDistance(_ first: LabColor, _ second: LabColor) -> Double {
    hypot(hypot(first.lightness - second.lightness, first.a - second.a), first.b - second.b)
  }

  private func updateCrop() {
    guard let slot = workflow?.review?.slot else { return }
    cropTask?.cancel()
    let requestedCorners = cropCorners
    isReprocessing = true
    cropError = nil
    cropTask = Task {
      do {
        let points = try requestedCorners.map {
          try ImagePoint(x: Double($0.x), y: Double($0.y))
        }
        let face = try await camera.reprocess(slot: slot, corners: points)
        try Task.checkCancellation()
        guard requestedCorners == cropCorners else { return }
        guard controller.sendScan(.updateReviewObservation(face)) == .accepted else {
          throw ScanError.invalidCrop
        }
      } catch is CancellationError {
      } catch {
        cropError = "Those corners do not form a readable face. Move them inside the image and try again."
        HapticFeedback.warning(
          enabled: controller.preferences.haptics,
          effectsEnabled: controller.preferences.effects)
      }
      if requestedCorners == cropCorners {
        isReprocessing = false
        cropTask = nil
      }
    }
  }

  private var classification: ScanClassification? {
    guard let draft = controller.pendingScan?.draft, let policy = Self.reviewPolicy else { return nil }
    return try? draft.classify(using: policy)
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

private struct CropEditor: View {
  let image: UIImage
  @Binding var corners: [CGPoint]
  let commit: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let rect = fittedRect(in: proxy.size)
      ZStack(alignment: .topLeading) {
        Image(uiImage: image).resizable().scaledToFit()
          .frame(width: proxy.size.width, height: proxy.size.height)
        Path { path in
          guard corners.count == 4 else { return }
          path.move(to: point(corners[0], in: rect))
          for corner in corners.dropFirst() { path.addLine(to: point(corner, in: rect)) }
          path.closeSubpath()
        }
        .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        ForEach(corners.indices, id: \.self) { index in
          let location = point(corners[index], in: rect)
          Circle().fill(.yellow).overlay(Circle().stroke(.black, lineWidth: 2))
            .frame(width: 34, height: 34)
            .position(location)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  corners[index] = normalized(value.location, in: rect)
                }
                .onEnded { _ in commit() })
            .accessibilityLabel("\(cornerName(index)) crop corner")
            .accessibilityHint("Drag to the matching corner of the cube face")
            .accessibilityAction(named: "Move left") { moveCorner(index, dx: -0.02, dy: 0) }
            .accessibilityAction(named: "Move right") { moveCorner(index, dx: 0.02, dy: 0) }
            .accessibilityAction(named: "Move up") { moveCorner(index, dx: 0, dy: -0.02) }
            .accessibilityAction(named: "Move down") { moveCorner(index, dx: 0, dy: 0.02) }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 16))
    }
  }

  private func fittedRect(in available: CGSize) -> CGRect {
    let scale = min(available.width / image.size.width, available.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    return CGRect(
      x: (available.width - size.width) / 2, y: (available.height - size.height) / 2,
      width: size.width, height: size.height)
  }

  private func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + normalized.y * rect.height)
  }

  private func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: min(1, max(0, (point.x - rect.minX) / rect.width)),
      y: min(1, max(0, (point.y - rect.minY) / rect.height)))
  }

  private func cornerName(_ index: Int) -> String {
    ["Top left", "Top right", "Bottom right", "Bottom left"][index]
  }

  private func moveCorner(_ index: Int, dx: CGFloat, dy: CGFloat) {
    corners[index] = CGPoint(
      x: min(1, max(0, corners[index].x + dx)),
      y: min(1, max(0, corners[index].y + dy)))
    commit()
  }
}
