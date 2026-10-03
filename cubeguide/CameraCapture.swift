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
  /// The on-screen capture grid; a frozen face's default crop is exactly this grid, and live
  /// face detection watches the same square.
  @ObservationIgnored var viewfinder: ViewfinderLayout? {
    didSet { updateFaceRegion() }
  }
  /// Live state of the face inside the viewfinder grid while the camera runs.
  private(set) var faceStatus: FaceStatus = .searching
  /// Increments each time a new face holds steady in the grid; the scan view captures on change.
  private(set) var autoCaptureRequests = 0
  @ObservationIgnored private var latestCells: [SIMD3<Float>]?
  @ObservationIgnored private var frozenCells: [SIMD3<Float>]?
  @ObservationIgnored private var acceptedCells: [SIMD3<Float>]?

  override convenience init() {
    self.init(sessionWorker: CameraSessionWorker())
  }

  init(sessionWorker: any CameraSessionControlling) {
    self.sessionWorker = sessionWorker
    super.init()
    sessionWorker.setFaceHandler { [weak self] cells, steady in
      Task { @MainActor in self?.faceObserved(cells, steady: steady) }
    }
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
    faceStatus = .searching
    updateFaceRegion()
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
        // stop() already stopped the worker; a newer start() owns the running session.
        guard !Task.isCancelled else { return }
        guard cameraEvent != nil else {
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
    let layout = viewfinder
    frozenCells = latestCells
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
          return try CameraImageProcessor.process(data, slot: slot, viewfinder: layout)
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

  /// Remembers the frozen face once accepted so it is not auto-captured again for the next slot.
  func rememberAcceptedFace() { acceptedCells = frozenCells }
  func forgetAcceptedFace() { acceptedCells = nil }

  private func updateFaceRegion() {
    sessionWorker.setFaceRegion(viewfinder, landscape: activeInterfaceOrientation().isLandscape)
  }

  private func faceObserved(_ cells: [SIMD3<Float>]?, steady: Bool) {
    guard cameraEvent != nil, startupTask == nil else { return }
    latestCells = cells
    let status: FaceStatus
    if let cells {
      if let acceptedCells, FaceDetector.sameFace(acceptedCells, cells) {
        status = .sameFace
      } else {
        status = .holding
        if steady { autoCaptureRequests &+= 1 }
      }
    } else {
      status = .searching
    }
    if faceStatus != status { faceStatus = status }
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

nonisolated enum FaceStatus: Equatable, Sendable { case searching, holding, sameFace }

protocol CameraSessionControlling: AnyObject, Sendable {
  nonisolated var session: AVCaptureSession { get }
  nonisolated func start() async throws
  nonisolated func stop()
  nonisolated func capture(delegate: AVCapturePhotoCaptureDelegate, rotationAngle: CGFloat)
  /// Receives grid cell colors (nil when no face is visible) and whether they just became steady.
  nonisolated func setFaceHandler(_ handler: @escaping @Sendable ([SIMD3<Float>]?, Bool) -> Void)
  /// The on-screen grid that live detection watches; nil pauses detection.
  nonisolated func setFaceRegion(_ viewfinder: ViewfinderLayout?, landscape: Bool)
}

private final class CameraSessionWorker: CameraSessionControlling, @unchecked Sendable {
  nonisolated let session = AVCaptureSession()
  nonisolated(unsafe) private let output = AVCapturePhotoOutput()
  nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
  nonisolated private let analyzer = FrameAnalyzer()
  nonisolated private let queue = DispatchQueue(
    label: "com.cubeguide.camera.session", qos: .userInitiated)
  nonisolated(unsafe) private var configured = false

  nonisolated func setFaceHandler(_ handler: @escaping @Sendable ([SIMD3<Float>]?, Bool) -> Void) {
    analyzer.queue.async { [analyzer] in analyzer.handler = handler }
  }

  nonisolated func setFaceRegion(_ viewfinder: ViewfinderLayout?, landscape: Bool) {
    analyzer.queue.async { [analyzer] in
      analyzer.viewfinder = viewfinder
      analyzer.landscape = landscape
    }
  }

  nonisolated func start() async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try configureIfNeeded()
          analyzer.queue.async { [analyzer] in analyzer.steadiness = FaceSteadiness() }
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
    // Multi-lens devices switch to a close-focus (macro) lens on their own when the cube is near.
    let types: [AVCaptureDevice.DeviceType] = [
      .builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera,
    ]
    guard
      let device = types.lazy.compactMap({
        AVCaptureDevice.default($0, for: .video, position: .back)
      }).first
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
    // Live detection only drives auto-capture; manual capture still works without it.
    if session.canAddOutput(videoOutput) {
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      videoOutput.setSampleBufferDelegate(analyzer, queue: analyzer.queue)
      session.addOutput(videoOutput)
    }
    analyzer.device = device
    // The input and output are attached now, so this session is configured even if the optional
    // focus/exposure preferences cannot be applied; failing here would leave a half-configured
    // session that rejects every later attempt to add the same input.
    configured = true
    guard (try? device.lockForConfiguration()) != nil else { return }
    defer { device.unlockForConfiguration() }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
    device.videoZoomFactor = CameraZoom.factor(for: device)
    device.isSubjectAreaChangeMonitoringEnabled = true
  }
}

nonisolated enum CameraZoom {
  /// Zoom so a 57 mm face fills the capture grid slightly beyond the wide lens's closest focus
  /// distance. Filling an unzoomed grid needs the cube about 8 cm from the lens, inside that
  /// distance, which is why close-up frames were blurry.
  static func factor(for device: AVCaptureDevice) -> CGFloat {
    let wide = device.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera } ?? device
    // Virtual devices start at the ultra-wide lens; their first switch-over factor is the wide lens.
    let base = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat($0.doubleValue) } ?? 1
    let extra = focusZoom(
      minimumFocusMillimeters: Double(wide.minimumFocusDistance),
      horizontalFieldOfView: Double(wide.activeFormat.videoFieldOfView))
    return min(device.activeFormat.videoMaxZoomFactor, max(1, base * CGFloat(extra)))
  }

  /// `gridFraction` is the grid's share of the frame's short side (about 0.77 on iPhone).
  static func focusZoom(
    minimumFocusMillimeters: Double, horizontalFieldOfView degrees: Double,
    faceMillimeters: Double = 57, gridFraction: Double = 0.75
  ) -> Double {
    guard minimumFocusMillimeters > 0, degrees > 0, degrees < 180 else { return 1 }
    // The short side of a 4:3 frame spans three quarters of the long side's tangent.
    let halfShortTangent = tan(degrees * .pi / 360) * 0.75
    let fillDistance = faceMillimeters / gridFraction / 2 / halfShortTangent
    return max(1, minimumFocusMillimeters * 1.1 / fillDistance)
  }
}

/// Finds a cube face in the live grid. Off-center cells must each be one even color and most
/// borders between cells must show the cube's dark gaps. Walls, tables, posters and blurred
/// frames fail these checks; a solved, single-color face passes. The center may carry a logo.
nonisolated enum FaceDetector {
  /// `side` is the grid's side in buffer pixels; the grid is centered in the buffer.
  static func cells(
    width: Int, height: Int, side: Double, pixel: (Int, Int) -> SIMD3<Float>
  ) -> [SIMD3<Float>]? {
    guard side > 9, side <= Double(min(width, height)) else { return nil }
    let originX = (Double(width) - side) / 2
    let originY = (Double(height) - side) / 2
    let cell = side / 3
    func sample(_ u: Double, _ v: Double) -> SIMD3<Float> {
      pixel(min(width - 1, Int(originX + u * cell)), min(height - 1, Int(originY + v * cell)))
    }
    var means: [SIMD3<Float>] = []
    for index in 0..<9 {
      // A 5 x 5 lattice over the cell's central half stays clear of sticker borders.
      let samples = (0..<25).map { step in
        sample(
          Double(index % 3) + 0.25 + Double(step % 5) * 0.125,
          Double(index / 3) + 0.25 + Double(step / 5) * 0.125)
      }
      let mean = samples.reduce(SIMD3<Float>.zero, +) / Float(samples.count)
      if index != 4, samples.contains(where: { distance($0, mean) > 45 }) { return nil }
      means.append(mean)
    }
    // Each of the 12 inner borders: darkest point across a band of ±20% of a cell around it.
    var gaps = 0
    for line in 1...2 {
      for along in 0..<3 {
        for vertical in [true, false] {
          let darkest = stride(from: -0.2, through: 0.2, by: 0.05).map { offset -> Float in
            let (across, length) = (Double(line) + offset, Double(along) + 0.5)
            return luminance(vertical ? sample(across, length) : sample(length, across))
          }.min() ?? 0
          let neighbors =
            vertical
            ? (along * 3 + line - 1, along * 3 + line) : ((line - 1) * 3 + along, line * 3 + along)
          let lighter = min(luminance(means[neighbors.0]), luminance(means[neighbors.1]))
          if darkest < lighter * 0.65 { gaps += 1 }
        }
      }
    }
    return gaps >= 9 ? means : nil
  }

  /// The grid's side in buffer pixels for the on-screen viewfinder.
  static func side(
    for viewfinder: ViewfinderLayout, landscape: Bool, bufferWidth: Int, bufferHeight: Int
  ) -> Double? {
    let long = Double(max(bufferWidth, bufferHeight))
    let short = Double(min(bufferWidth, bufferHeight))
    let upright = landscape ? (long, short) : (short, long)
    guard
      let corners = try? ViewfinderCrop.corners(
        preview: .init(
          width: Double(viewfinder.preview.width), height: Double(viewfinder.preview.height)),
        gridSide: Double(viewfinder.gridSide), image: .init(width: upright.0, height: upright.1))
    else { return nil }
    return (corners[1].x - corners[0].x) * upright.0
  }

  /// True when two observations show the same face, so it is not captured twice in a row.
  static func sameFace(_ first: [SIMD3<Float>], _ second: [SIMD3<Float>]) -> Bool {
    zip(first, second).map { distance($0, $1) }.reduce(0, +) / Float(first.count) < 30
  }

  static func distance(_ first: SIMD3<Float>, _ second: SIMD3<Float>) -> Float {
    let delta = first - second
    return (delta * delta).sum().squareRoot()
  }

  static func luminance(_ color: SIMD3<Float>) -> Float {
    0.299 * color.x + 0.587 * color.y + 0.114 * color.z
  }
}

/// Reports a face once per steady streak: same cells for several analyzed frames, lens in focus.
nonisolated struct FaceSteadiness {
  static let requiredFrames = 5
  private var previous: [SIMD3<Float>]?
  private var steadyFrames = 0
  private var reported = false

  init() {}

  mutating func update(_ cells: [SIMD3<Float>]?, focused: Bool) -> Bool {
    let stable =
      if let cells, let previous {
        zip(cells, previous).allSatisfy { FaceDetector.distance($0, $1) < 18 }
      } else { false }
    previous = cells
    guard stable else {
      steadyFrames = 0
      reported = false
      return false
    }
    guard focused else { return false }
    steadyFrames += 1
    guard steadyFrames >= Self.requiredFrames, !reported else { return false }
    reported = true
    return true
  }
}

nonisolated private final class FrameAnalyzer: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable
{
  // Mutable state is only touched on `queue`.
  let queue = DispatchQueue(label: "com.cubeguide.camera.faces", qos: .userInitiated)
  nonisolated(unsafe) var handler: (@Sendable ([SIMD3<Float>]?, Bool) -> Void)?
  nonisolated(unsafe) var steadiness = FaceSteadiness()
  nonisolated(unsafe) var viewfinder: ViewfinderLayout?
  nonisolated(unsafe) var landscape = false
  nonisolated(unsafe) weak var device: AVCaptureDevice?
  nonisolated(unsafe) private var frame = 0

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    frame &+= 1
    // About ten analyses per second is plenty and keeps the camera queue light.
    guard frame % 3 == 0, let handler, let viewfinder,
      let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    guard
      let side = FaceDetector.side(
        for: viewfinder, landscape: landscape, bufferWidth: width, bufferHeight: height)
    else { return }
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    // The grid is a centered square, so it covers the same pixels whatever the buffer rotation.
    let cells = FaceDetector.cells(width: width, height: height, side: side) { x, y in
      let pixel = bytes + y * rowBytes + x * 4
      return SIMD3(Float(pixel[2]), Float(pixel[1]), Float(pixel[0]))
    }
    let steady = steadiness.update(cells, focused: device?.isAdjustingFocus == false)
    handler(cells, steady)
  }
}

enum CaptureRotation {
  nonisolated static func angle(for orientation: UIInterfaceOrientation) -> CGFloat {
    switch orientation {
    case .portrait: 90
    case .portraitUpsideDown: 270
    case .landscapeRight: 0
    case .landscapeLeft: 180
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

  /// A new capture starts from the grid the user aligned the face with.
  nonisolated static func process(
    _ data: Data, slot: Face, viewfinder: ViewfinderLayout?
  ) throws -> Result {
    guard let source = UIImage(data: data) else { throw CameraError.invalidImage }
    return try processSource(
      source, slot: slot, corners: corners(for: viewfinder, imageSize: source.size))
  }

  /// Normalized crops depend only on the aspect ratio, so the upright source size suffices.
  nonisolated static func corners(for viewfinder: ViewfinderLayout?, imageSize: CGSize)
    -> [ImagePoint]
  {
    guard let viewfinder,
      let corners = try? ViewfinderCrop.corners(
        preview: .init(
          width: Double(viewfinder.preview.width), height: Double(viewfinder.preview.height)),
        gridSide: Double(viewfinder.gridSide),
        image: .init(width: Double(imageSize.width), height: Double(imageSize.height)))
    else { return defaultCorners() }
    return corners
  }

  nonisolated static func defaultCorners() -> [ImagePoint] {
    // Fail closed if ImagePoint's bounds ever change instead of crashing camera startup.
    [
      (0.14, 0.14), (0.86, 0.14), (0.86, 0.86), (0.14, 0.86),
    ].compactMap { try? ImagePoint(x: $0.0, y: $0.1) }
  }

  nonisolated private static func recordedProvenance(for orientation: UIImage.Orientation)
    -> (FrameOrientation, Bool)
  {
    switch orientation {
    case .up: return (.up, false)
    case .upMirrored: return (.up, true)
    case .down: return (.down, false)
    case .downMirrored: return (.down, true)
    case .left: return (.left, false)
    case .leftMirrored: return (.left, true)
    case .right: return (.right, false)
    case .rightMirrored: return (.right, true)
    @unknown default: return (.up, false)
    }
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
    format.preferredRange = .standard
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let cgImage = image.cgImage, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw CameraError.invalidImage
    }
    let width = cgImage.width
    let height = cgImage.height
    var rgba = Array(repeating: UInt8.zero, count: width * height * 4)
    // A plain bitmap context already stores the image's top row first, which is the row order
    // SRGBImage, the crop corners and the sampler use. Flipping here would read faces upside down.
    let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: sRGB,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw CameraError.invalidImage }
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
    let (recordedOrientation, recordedMirroring) = recordedProvenance(
      for: source.imageOrientation)
    let metadata = try CaptureMetadata(
      width: width, height: height, sourceOrientation: recordedOrientation,
      sourceMirrored: recordedMirroring,
      corners: corners, pose: pose, samplingVersion: "homography-srgb-d65-v1")
    return try Result(
      image: image,
      face: ScanFace(slot: slot, measurements: measurements, metadata: metadata),
      quality: CameraQuality.assess(rgb))
  }
}

struct ViewfinderLayout: Equatable, Sendable {
  let preview: CGSize
  let gridSide: CGFloat
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
