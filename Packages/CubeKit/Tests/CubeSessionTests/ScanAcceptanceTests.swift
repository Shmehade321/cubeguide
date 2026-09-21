import CubeCore
import CubeScan
import CubeSolver3
import Foundation
import Testing

@testable import CubeSession

private let acceptancePalette = try! CenterPalette([
  .green, .white, .orange, .blue, .yellow, .red,
])
private let acceptancePolicy = try! ScanPolicy(
  version: "acceptance-v1", maximumSpread: 5, minimumMargin: 5,
  maximumDistance: 10, minimumCenterSeparation: 10)

private func acceptedScan(
  _ state: Facelets = .solved, purpose: ScanPurpose = .newCube,
  retainedGuide: SaveID? = nil, revision: UInt64 = 20
) throws -> PendingScan {
  let centerValues = [10.0, 25, 40, 55, 70, 85]
  let tops: [Face] = [.back, .up, .up, .front, .up, .up]
  var draft = ScanDraft(revision: revision - 6)
  for slot in ScanDraft.captureOrder {
    let base = Int(slot.rawValue) * 9
    let measurements = try (0..<9).map { cell -> ColorMeasurement in
      let label = state.faces[base + cell]
      let value = centerValues[Int(label.rawValue)]
      return try ColorMeasurement(
        median: LabColor(lightness: value, a: 0, b: 0),
        display: DisplaySRGB(red: value / 100, green: value / 100, blue: value / 100),
        spread: 1, sampleCount: 100)
    }
    let metadata = try CaptureMetadata(
      width: 300, height: 300, sourceOrientation: .up, sourceMirrored: false,
      corners: [
        ImagePoint(x: 0, y: 0), ImagePoint(x: 1, y: 0),
        ImagePoint(x: 1, y: 1), ImagePoint(x: 0, y: 1),
      ], pose: CubeOrientation(front: slot, top: tops[Int(slot.rawValue)]),
      samplingVersion: "acceptance-fixture-v1")
    draft = try draft.accepting(
      ScanFace(
        slot: slot, measurements: measurements, metadata: metadata,
        centerName: acceptancePalette.colors[Int(slot.rawValue)]))
  }
  return try PendingScan(draft: draft, purpose: purpose, retainedGuide: retainedGuide)
}

@MainActor
@Test("R02/R05/R10: confirmed solved scan saves camera-verified completion and retires its draft")
func acceptSolvedScan() async throws {
  let store = SessionStore()
  let scan = try acceptedScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let controller = SessionController(storage: store, solver: SolverService())
  await controller.load()
  let classification = try scan.draft.classify(using: acceptancePolicy)
  #expect(
    controller.acceptReviewedScan(classification, confirmed: false)
      == .rejected(.confirmationRequired))
  #expect(controller.acceptReviewedScan(classification, confirmed: true) == .accepted)
  await controller.waitForEffects()
  #expect(controller.scanWorkflow == nil && controller.pendingScan == nil)
  #expect(controller.session.phase == .completed)
  #expect(controller.session.completion == .scanVerified)
  let restored = try await store.restore()
  #expect(restored.pendingScan == nil && restored.session.completion == .scanVerified)
}

@MainActor
@Test("R03: uncertain and stale classifications remain editable scans")
func rejectUnreviewedScan() async throws {
  let store = SessionStore()
  let scan = try acceptedScan()
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let controller = SessionController(storage: store, solver: SolverService())
  await controller.load()
  let strict = try ScanPolicy(
    version: "strict", maximumSpread: 0, minimumMargin: 100,
    maximumDistance: 0, minimumCenterSeparation: 100)
  #expect(
    controller.acceptReviewedScan(try scan.draft.classify(using: strict), confirmed: true)
      == .rejected(.scanNeedsReview))
  let stale = try acceptedScan(revision: 30).draft.classify(using: acceptancePolicy)
  #expect(
    controller.acceptReviewedScan(stale, confirmed: true)
      == .rejected(.unavailableEvent))
  #expect(controller.scanWorkflow != nil && controller.pendingScan == scan)
}

@MainActor
@Test(
  "R02-R06: a reviewed scrambled scan reaches consent and the real solver only after acceptance")
func acceptScrambledScan() async throws {
  let state = Facelets.solved.applying([Move(face: .right, turns: .clockwise)])
  let store = SessionStore()
  let scan = try acceptedScan(state)
  try await store.saveScanDraft(scan, lease: store.currentLease())
  let controller = SessionController(storage: store, solver: SolverService())
  await controller.load()
  #expect(
    controller.acceptReviewedScan(
      try scan.draft.classify(using: acceptancePolicy), confirmed: true) == .accepted)
  #expect(controller.session.phase == .offer && controller.session.confirmedCube?.facelets == state)
  #expect(try await store.load() == nil)
  #expect(controller.send(.consent(true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .guide && controller.session.plan?.original == state)
  #expect(try await store.restore().pendingScan == nil)
}
