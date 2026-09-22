@preconcurrency import AVFoundation
import CubeCore
import CubeScan
import CubeSession
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraCapture: NSObject, ScanCamera {
  var session: AVCaptureSession { sessionWorker.session }
  private let sessionWorker: any CameraSessionControlling
  private var delegate: PhotoDelegate?
  private var attemptGuard = CaptureAttemptGuard()
  private var cameraEvent: (@MainActor @Sendable (ScanCameraEvent) -> Void)?
  private var startupTask: Task<Void, Never>?
  private var processingTask: Task<Void, Never>?
  private var notificationTokens: [NSObjectProtocol] = []
  private var frozenData: Data?
  private(set) var frozenImage: UIImage?
  private(set) var qualityHints: [String] = []

  override convenience init() {
    self.init(sessionWorker: CameraSessionWorker())
  }

  init(sessionWorker: any CameraSessionControlling) {
    self.sessionWorker = sessionWorker
    super.init()
    let center = NotificationCenter.default
    notificationTokens = [
      center.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification, object: sessionWorker.session,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.sessionInterrupted() }
      },
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification, object: sessionWorker.session,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.sessionInterrupted() }
      },
    ]
  }

  isolated deinit {
    for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
  }

  func start(slot: Face, event: @escaping @MainActor @Sendable (ScanCameraEvent) -> Void) {
    startupTask?.cancel()
    cameraEvent = event
    startupTask = Task { [weak self] in
      guard let self else { return }
      let authorized: Bool
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: authorized = true
      case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
      default: authorized = false
      }
      guard !Task.isCancelled, cameraEvent != nil else { return }
      guard authorized else {
        cameraEvent = nil
        startupTask = nil
        event(.interrupted(.permissionDenied))
        return
      }
      do {
        try await sessionWorker.start()
        guard !Task.isCancelled, cameraEvent != nil else {
          sessionWorker.stop()
          return
        }
        startupTask = nil
        event(.ready)
      } catch {
        guard !Task.isCancelled else { return }
        cameraEvent = nil
        startupTask = nil
        event(.interrupted(.cameraUnavailable))
      }
    }
  }

  func freeze(
    id: ScanOperationID, slot: Face,
    completion: @escaping @MainActor @Sendable (ScanCameraResult) -> Void
  ) {
    let token = attemptGuard.begin(id)
    let proxy = PhotoDelegate { [weak self] data in
      guard let self else { return }
      guard self.attemptGuard.matches(id, token: token), let data else {
        guard self.attemptGuard.complete(id, token: token) else { return }
        self.delegate = nil
        completion(.failed(.captureFailed))
        return
      }
      self.processingTask?.cancel()
      self.processingTask = Task { [weak self] in
        let result = await Task.detached(priority: .userInitiated) {
          try Task.checkCancellation()
          return try CameraImageProcessor.process(data, slot: slot)
        }.result
        guard let self, !Task.isCancelled,
          self.attemptGuard.complete(id, token: token)
        else { return }
        self.delegate = nil
        self.processingTask = nil
        switch result {
        case .success(let processed):
          self.frozenData = data
          self.frozenImage = processed.image
          self.qualityHints = processed.quality.hints
          completion(.captured(processed.face))
        case .failure:
          completion(.failed(.invalidObservation))
        }
      }
    }
    delegate = proxy
    sessionWorker.capture(
      delegate: proxy,
      rotationAngle: CaptureRotation.angle(for: activeInterfaceOrientation()))
  }

  func stop() {
    startupTask?.cancel()
    startupTask = nil
    attemptGuard.invalidate()
    processingTask?.cancel()
    processingTask = nil
    cameraEvent = nil
    sessionWorker.stop()
  }

  func discardFrame() {
    attemptGuard.invalidate()
    processingTask?.cancel()
    processingTask = nil
    frozenImage = nil
    frozenData = nil
    qualityHints = []
    delegate = nil
  }

  func reprocess(slot: Face, corners: [ImagePoint]) async throws -> ScanFace {
    guard let data = frozenData else { throw CameraError.invalidImage }
    let result = try await Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      return try CameraImageProcessor.process(data, slot: slot, corners: corners)
    }.value
    guard frozenImage != nil else { throw CancellationError() }
    return result.face
  }

  private func sessionInterrupted() {
    attemptGuard.invalidate()
    processingTask?.cancel()
    processingTask = nil
    cameraEvent?(.interrupted(.cameraUnavailable))
    cameraEvent = nil
  }

  private func activeInterfaceOrientation() -> UIInterfaceOrientation {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
      .first ?? .portrait
  }
}

struct CaptureAttemptGuard {
  private var generation: UInt64 = 0
  private var active: (id: ScanOperationID, token: UInt64)?

  mutating func begin(_ id: ScanOperationID) -> UInt64 {
    generation &+= 1
    active = (id, generation)
    return generation
  }

  mutating func complete(_ id: ScanOperationID, token: UInt64) -> Bool {
    guard matches(id, token: token) else { return false }
    active = nil
    return true
  }

  func matches(_ id: ScanOperationID, token: UInt64) -> Bool {
    active?.id == id && active?.token == token
  }

  mutating func invalidate() {
    generation &+= 1
    active = nil
  }
}

protocol CameraSessionControlling: AnyObject, Sendable {
  nonisolated var session: AVCaptureSession { get }
  nonisolated func start() async throws
  nonisolated func stop()
  nonisolated func capture(delegate: AVCapturePhotoCaptureDelegate, rotationAngle: CGFloat)
}

private final class CameraSessionWorker: CameraSessionControlling, @unchecked Sendable {
  nonisolated let session = AVCaptureSession()
  nonisolated(unsafe) private let output = AVCapturePhotoOutput()
  nonisolated private let queue = DispatchQueue(
    label: "com.cubeguide.camera.session", qos: .userInitiated)
  nonisolated(unsafe) private var configured = false

  nonisolated func start() async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try configureIfNeeded()
          if !session.isRunning { session.startRunning() }
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  nonisolated func stop() {
    queue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  nonisolated func capture(delegate: AVCapturePhotoCaptureDelegate, rotationAngle: CGFloat) {
    queue.async { [output] in
      let settings = AVCapturePhotoSettings()
      settings.photoQualityPrioritization = .quality
      if let connection = output.connection(with: .video),
        connection.isVideoRotationAngleSupported(rotationAngle)
      {
        connection.videoRotationAngle = rotationAngle
      }
      output.capturePhoto(with: settings, delegate: delegate)
    }
  }

  nonisolated private func configureIfNeeded() throws {
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
    output.maxPhotoQualityPrioritization = .quality
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    device.isSubjectAreaChangeMonitoringEnabled = true
    configured = true
  }
}

enum CaptureRotation {
  nonisolated static func angle(for orientation: UIInterfaceOrientation) -> CGFloat {
    switch orientation {
    case .portrait: 90
    case .portraitUpsideDown: 270
    case .landscapeLeft: 0
    case .landscapeRight: 180
    default: 90
    }
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
  struct Result: @unchecked Sendable {
    let image: UIImage
    let face: ScanFace
    let quality: CameraQualityAssessment
  }

  @MainActor
  static func process(
    _ source: UIImage, slot: Face, corners: [ImagePoint] = defaultCorners()
  ) throws -> Result {
    try processSource(source, slot: slot, corners: corners)
  }

  nonisolated static func process(
    _ data: Data, slot: Face, corners: [ImagePoint] = defaultCorners()
  ) throws -> Result {
    guard let source = UIImage(data: data) else { throw CameraError.invalidImage }
    return try processSource(source, slot: slot, corners: corners)
  }

  nonisolated static func defaultCorners() -> [ImagePoint] {
    // Fail closed if ImagePoint's bounds ever change instead of crashing camera startup.
    [
      (0.14, 0.14), (0.86, 0.14), (0.86, 0.86), (0.14, 0.86),
    ].compactMap { try? ImagePoint(x: $0.0, y: $0.1) }
  }

  nonisolated private static func processSource(
    _ source: UIImage, slot: Face, corners: [ImagePoint]
  ) throws -> Result {
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
    let measurements = try FaceImageSampler.measurements(in: sampledImage, corners: corners)
    let tops: [Face] = [.back, .up, .up, .front, .up, .up]
    let pose = try CubeOrientation(front: slot, top: tops[Int(slot.rawValue)])
    let metadata = try CaptureMetadata(
      width: width, height: height, sourceOrientation: .up, sourceMirrored: false,
      corners: corners, pose: pose, samplingVersion: "homography-srgb-d65-v1")
    return try Result(
      image: image,
      face: ScanFace(slot: slot, measurements: measurements, metadata: metadata),
      quality: CameraQuality.assess(rgb))
  }
}

struct CameraQualityAssessment: Equatable, Sendable {
  let hints: [String]
}

enum CameraQuality {
  /// Advisory thresholds only. They never accept or reject a face; corpus qualification must
  /// calibrate any future blocking policy.
  nonisolated static func assess(_ rgb: [UInt8]) -> CameraQualityAssessment {
    guard rgb.count >= 6, rgb.count.isMultiple(of: 3) else {
      return CameraQualityAssessment(hints: ["Retake the picture; the image could not be checked."])
    }
    var luminances: [Double] = []
    luminances.reserveCapacity(rgb.count / 3)
    var clipped = 0
    for offset in stride(from: 0, to: rgb.count, by: 3) {
      let value = (0.2126 * Double(rgb[offset]) + 0.7152 * Double(rgb[offset + 1])
        + 0.0722 * Double(rgb[offset + 2])) / 255
      luminances.append(value)
      if rgb[offset] >= 250 && rgb[offset + 1] >= 250 && rgb[offset + 2] >= 250 { clipped += 1 }
    }
    let mean = luminances.reduce(0, +) / Double(luminances.count)
    let deviation = sqrt(luminances.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminances.count))
    let adjacentChange = zip(luminances, luminances.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
      / Double(max(1, luminances.count - 1))
    var hints: [String] = []
    if mean < 0.16 { hints.append("Add more even light before accepting this face.") }
    if mean > 0.90 { hints.append("Reduce direct light before accepting this face.") }
    if Double(clipped) / Double(luminances.count) > 0.12 {
      hints.append("Move the cube to remove bright glare from its stickers.")
    }
    if deviation < 0.035 { hints.append("Check that sticker edges and colors are clearly visible.") }
    if adjacentChange < 0.004 { hints.append("Hold the phone steady and retake if the image looks soft.") }
    return CameraQualityAssessment(hints: hints)
  }
}

struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.layerView?.session = session
    view.layerView?.videoGravity = .resizeAspectFill
    return view
  }
  func updateUIView(_ uiView: PreviewView, context: Context) {
    let orientation = uiView.window?.windowScene?.interfaceOrientation ?? .portrait
    let angle = CaptureRotation.angle(for: orientation)
    if uiView.layerView?.connection?.isVideoRotationAngleSupported(angle) == true {
      uiView.layerView?.connection?.videoRotationAngle = angle
    }
  }
}

final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var layerView: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
}
