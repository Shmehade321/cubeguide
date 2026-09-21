@preconcurrency import AVFoundation
import CubeCore
import CubeScan
import CubeSession
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraCapture: NSObject, ScanCamera {
  let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private var configured = false
  private var delegate: PhotoDelegate?
  private(set) var frozenImage: UIImage?

  func start(slot: Face, event: @escaping @MainActor @Sendable (ScanCameraEvent) -> Void) {
    Task {
      let authorized: Bool
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: authorized = true
      case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
      default: authorized = false
      }
      guard authorized else {
        event(.interrupted(.permissionDenied))
        return
      }
      do {
        try configureIfNeeded()
        if !session.isRunning { session.startRunning() }
        event(.ready)
      } catch {
        event(.interrupted(.cameraUnavailable))
      }
    }
  }

  func freeze(
    id: ScanOperationID, slot: Face,
    completion: @escaping @MainActor @Sendable (ScanCameraResult) -> Void
  ) {
    guard configured else {
      completion(.failed(.cameraUnavailable))
      return
    }
    let proxy = PhotoDelegate { [weak self] data in
      guard let self else { return }
      self.delegate = nil
      guard let data, let image = UIImage(data: data) else {
        completion(.failed(.captureFailed))
        return
      }
      do {
        let processed = try CameraImageProcessor.process(image, slot: slot)
        self.frozenImage = processed.image
        completion(.captured(processed.face))
      } catch {
        completion(.failed(.invalidObservation))
      }
    }
    delegate = proxy
    output.capturePhoto(with: AVCapturePhotoSettings(), delegate: proxy)
  }

  func stop() {
    if session.isRunning { session.stopRunning() }
  }

  func discardFrame() {
    frozenImage = nil
    delegate = nil
  }

  private func configureIfNeeded() throws {
    guard !configured else { return }
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    else { throw CameraError.unavailable }
    let input = try AVCaptureDeviceInput(device: device)
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw CameraError.unavailable
    }
    session.addInput(input)
    session.addOutput(output)
    configured = true
  }
}

private enum CameraError: Error { case unavailable, invalidImage }

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  private let completion: @MainActor @Sendable (Data?) -> Void
  init(completion: @escaping @MainActor @Sendable (Data?) -> Void) {
    self.completion = completion
  }
  nonisolated func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
    error: (any Error)?
  ) {
    let data = error == nil ? photo.fileDataRepresentation() : nil
    Task { @MainActor in completion(data) }
  }
}

enum CameraImageProcessor {
  struct Result {
    let image: UIImage
    let face: ScanFace
  }

  @MainActor
  static func process(_ source: UIImage, slot: Face) throws -> Result {
    guard source.size.width > 0, source.size.height > 0 else { throw CameraError.invalidImage }
    let scale = min(1, 1920 / max(source.size.width, source.size.height))
    let size = CGSize(
      width: max(1, floor(source.size.width * scale)),
      height: max(1, floor(source.size.height * scale)))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let cgImage = image.cgImage else { throw CameraError.invalidImage }
    let width = cgImage.width
    let height = cgImage.height
    var rgba = Array(repeating: UInt8.zero, count: width * height * 4)
    guard
      let context = CGContext(
        data: &rgba, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CameraError.invalidImage }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    var rgb: [UInt8] = []
    rgb.reserveCapacity(width * height * 3)
    for offset in stride(from: 0, to: rgba.count, by: 4) {
      rgb.append(rgba[offset])
      rgb.append(rgba[offset + 1])
      rgb.append(rgba[offset + 2])
    }
    let sampledImage = try SRGBImage(width: width, height: height, bytes: rgb)
    let corners = try [
      ImagePoint(x: 0.14, y: 0.14), ImagePoint(x: 0.86, y: 0.14),
      ImagePoint(x: 0.86, y: 0.86), ImagePoint(x: 0.14, y: 0.86),
    ]
    let measurements = try FaceImageSampler.measurements(
      in: sampledImage, corners: corners, samplesPerAxis: 8)
    let tops: [Face] = [.back, .up, .up, .front, .up, .up]
    let pose = try CubeOrientation(front: slot, top: tops[Int(slot.rawValue)])
    let metadata = try CaptureMetadata(
      width: width, height: height, sourceOrientation: .up, sourceMirrored: false,
      corners: corners, pose: pose, samplingVersion: "homography-srgb-d65-v1")
    return try Result(
      image: image,
      face: ScanFace(slot: slot, measurements: measurements, metadata: metadata))
  }
}

struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.layerView.session = session
    view.layerView.videoGravity = .resizeAspectFill
    return view
  }
  func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
