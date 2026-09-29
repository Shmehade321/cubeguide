import CubeSolver3

import Foundation
import Testing
@testable import CubeSession

@Test("R18: preferences survive reopening and deletion restores documented defaults")
func preferencesPersistenceAndDeletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  let defaults = try await store.loadPreferences()
  #expect(defaults.narration && !defaults.effects && defaults.haptics)
  #expect(defaults.speed == .normal && defaults.showColorLabels)
  var changed = defaults
  changed.narration = false
  changed.effects = true
  changed.haptics = false
  changed.speed = .fast
  changed.showColorLabels = false
  let lease = await store.currentLease()
  try await store.savePreferences(changed, lease: lease)
  let reopened = SessionStore(directory: directory)
  #expect(try await reopened.loadPreferences() == changed)
  _ = try await store.delete(lease: lease)
  #expect(try await reopened.loadPreferences() == defaults)
  await #expect(throws: SessionStoreError.staleLease) {
    try await store.savePreferences(changed, lease: lease)
  }
}

@Test("R18: malformed, oversized and future preferences survive rejected writes until deletion")
func preferencesPreserveUnknown() async throws {
  for bytes in [Data("broken".utf8), Data("{\"schema\":2}".utf8),
    Data(repeating: 32, count: CheckedArchive.maximumBytes + 1)] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("preferences.json")
    try bytes.write(to: file)
    let store = SessionStore(directory: directory)
    await #expect(throws: (any Error).self) { try await store.loadPreferences() }
    let lease = await store.currentLease()
    await #expect(throws: (any Error).self) {
      try await store.savePreferences(AppPreferences(), lease: lease)
    }
    #expect(try Data(contentsOf: file) == bytes)
    _ = try await store.delete(lease: lease)
    #expect(try await store.loadPreferences() == AppPreferences())
  }
}

private enum PreferencesFault: Error { case interrupted }

@Test("R18: failed preference replacement reopens a whole record and explicit retry settles")
func preferencesWriteBoundaries() async throws {
  for boundary in [StoreBoundary.beforeWrite, .temporarySynced, .beforeReplace, .afterReplace] {
    let directory = try storeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let seed = SessionStore(directory: directory)
    let defaults = AppPreferences()
    try await seed.savePreferences(defaults, lease: seed.currentLease())
    var changed = defaults
    changed.speed = .slow
    changed.narration = false
    let failing = SessionStore(directory: directory, checkpoint: { reached in
      if reached == boundary { throw PreferencesFault.interrupted }
    })
    let candidate = changed
    await #expect(throws: PreferencesFault.interrupted) {
      try await failing.savePreferences(candidate, lease: failing.currentLease())
    }
    let reopened = SessionStore(directory: directory)
    #expect(try await reopened.loadPreferences() == (boundary == .afterReplace ? changed : defaults))
    try await reopened.savePreferences(changed, lease: reopened.currentLease())
    #expect(try await reopened.loadPreferences() == changed)
  }
}

@MainActor @Test("R18: controller loads, saves and resets preferences only after durable success")
func preferencesController() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(directory: directory)
  var saved = AppPreferences()
  saved.speed = .slow
  try await store.savePreferences(saved, lease: store.currentLease())
  let controller = SessionController(storage: store, solver: SolverService())
  #expect(controller.savePreferences(saved) == .rejected(.unavailableEvent))
  await controller.load()
  #expect(controller.preferences == saved)
  var changed = saved
  changed.effects = true
  #expect(controller.savePreferences(changed) == .accepted)
  #expect(controller.preferencesStatus == .saving)
  #expect(controller.preferences == saved)
  await controller.waitForEffects()
  #expect(controller.preferencesStatus == .idle)
  #expect(controller.preferences == changed)
  #expect(try await store.loadPreferences() == changed)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  #expect(controller.savePreferences(changed) == .rejected(.unavailableEvent))
  await controller.waitForEffects()
  #expect(controller.preferences == AppPreferences())
  #expect(controller.session.phase == .home)
}

@MainActor @Test("R18: deletion wins over an outstanding settings callback and scan cannot strand it")
func preferencesDeletionDuringSave() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let storage = ControlledStorage(real)
  let gate = ControllerGate()
  await storage.gatePreferences(gate)
  let controller = SessionController(storage: storage, solver: SolverService(), camera: RecordingScanCamera())
  await controller.load()
  var changed = AppPreferences()
  changed.effects = true
  #expect(controller.savePreferences(changed) == .accepted)
  await gate.waitUntilEntered()
  #expect(await controller.startScan(purpose: .newCube) == .rejected(.unavailableEvent))
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.preferences == AppPreferences())
  #expect(controller.preferencesStatus == .idle)
  #expect(controller.session.phase == .home)
  #expect(try await real.loadPreferences() == AppPreferences())
}

@MainActor @Test("R18: ambiguous preference failure retains the exact candidate for explicit retry")
func preferencesFailureRetry() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let storage = ControlledStorage(real)
  let controller = SessionController(storage: storage, solver: SolverService())
  await controller.load()
  await storage.failNextPreferences()
  var changed = AppPreferences()
  changed.narration = false
  changed.speed = .fast
  #expect(controller.savePreferences(changed) == .accepted)
  await controller.waitForEffects()
  #expect(controller.preferencesStatus == .failed)
  #expect(controller.preferences == AppPreferences())
  #expect(try await real.loadPreferences() == changed)
  #expect(controller.retryPreferences() == .accepted)
  await controller.waitForEffects()
  #expect(controller.preferencesStatus == .idle)
  #expect(controller.preferences == changed)
  #expect(controller.retryPreferences() == .rejected(.unavailableEvent))
}

@Test("R12: system differentiation forces color labels without changing the stored preference")
func preferencesColorLabels() {
  var value = AppPreferences()
  #expect(value.colorLabelsEnabled(differentiateWithoutColor: false))
  value.showColorLabels = false
  #expect(!value.colorLabelsEnabled(differentiateWithoutColor: false))
  #expect(value.colorLabelsEnabled(differentiateWithoutColor: true))
  #expect(!value.showColorLabels)
  #expect(!value.colorLabelsEnabled(differentiateWithoutColor: false))
}

@MainActor @Test("R13/R18: settings persistence never suppresses capture interruption")
func preferencesDuringCaptureInterruption() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  let scan = try pendingScan()
  try await real.saveScanDraft(scan, lease: real.currentLease())
  let storage = ControlledStorage(real)
  let gate = ControllerGate()
  await storage.gatePreferences(gate)
  let camera = RecordingScanCamera()
  let controller = SessionController(storage: storage, solver: SolverService(), camera: camera)
  await controller.load()
  #expect(controller.sendScan(.resume(confirmedUnchanged: true)) == .accepted)
  #expect(controller.savePreferences(AppPreferences()) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.send(.background) == .accepted)
  #expect(controller.scanWorkflow?.phase == .pausedCapture)
  #expect(!controller.isCameraReady)
  #expect(controller.pendingScan == scan)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.preferencesStatus == .idle)
}

/// Settings controls enable from `canSavePreferences`, so it must predict the save outcome exactly.
@MainActor private func expectPreferencesAvailable(
  _ controller: SessionController, _ available: Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  #expect(controller.canSavePreferences == available, sourceLocation: sourceLocation)
  var next = controller.preferences
  next.haptics.toggle()
  guard available else {
    #expect(
      controller.savePreferences(next) == .rejected(.unavailableEvent),
      sourceLocation: sourceLocation)
    return
  }
  #expect(controller.savePreferences(next) == .accepted, sourceLocation: sourceLocation)
  await controller.waitForEffects()
  #expect(controller.preferences == next, sourceLocation: sourceLocation)
}

@MainActor @Test("R18: settings availability tracks loading, an in-flight save and scan start")
func preferencesAvailabilityLoadSaveAndScanStart() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let restoreGate = ControllerGate()
  let storage = ControlledStorage(SessionStore(directory: directory), restoreGate: restoreGate)
  let controller = SessionController(
    storage: storage, solver: SolverService(), camera: RecordingScanCamera())
  await expectPreferencesAvailable(controller, false)
  let loading = Task { await controller.load() }
  await restoreGate.waitUntilEntered()
  #expect(controller.loadStatus == .loading)
  await expectPreferencesAvailable(controller, false)
  await restoreGate.release()
  await loading.value
  await expectPreferencesAvailable(controller, true)

  let preferencesGate = ControllerGate()
  await storage.gatePreferences(preferencesGate)
  #expect(controller.savePreferences(AppPreferences()) == .accepted)
  await preferencesGate.waitUntilEntered()
  #expect(controller.preferencesStatus == .saving)
  await expectPreferencesAvailable(controller, false)
  await preferencesGate.release()
  await controller.waitForEffects()
  await expectPreferencesAvailable(controller, true)

  let scanGate = ControllerGate()
  await storage.gateNextRestore(scanGate)
  let starting = Task { await controller.startScan(purpose: .newCube) }
  await scanGate.waitUntilEntered()
  #expect(controller.isStartingScan)
  await expectPreferencesAvailable(controller, false)
  await scanGate.release()
  #expect(await starting.value == .accepted)
  await expectPreferencesAvailable(controller, true)
}

@MainActor @Test("R18: settings are unavailable after a failed load until deletion recovers it")
func preferencesAvailabilityLoadFailure() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("corrupt".utf8).write(to: directory.appendingPathComponent("draft.json"))
  let controller = SessionController(
    storage: SessionStore(directory: directory), solver: SolverService())
  await controller.load()
  #expect(controller.loadStatus == .failed)
  await expectPreferencesAvailable(controller, false)
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  await controller.waitForEffects()
  #expect(controller.loadStatus == .ready)
  await expectPreferencesAvailable(controller, true)
}

@MainActor @Test("R18: settings stay unavailable through a draft discard and its failure")
func preferencesAvailabilityDiscard() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  try await real.saveScanDraft(pendingScan(), lease: real.currentLease())
  let storage = ControlledStorage(real)
  let gate = ControllerGate()
  await storage.configureDiscard(fail: true, gate: gate)
  let controller = SessionController(storage: storage, solver: SolverService())
  await controller.load()
  #expect(controller.canSavePreferences)
  #expect(controller.discardDraft(confirmed: true) == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.discardStatus == .saving)
  await expectPreferencesAvailable(controller, false)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.discardStatus == .failed)
  await expectPreferencesAvailable(controller, false)
  #expect(controller.retryDraftDiscard() == .accepted)
  await controller.waitForEffects()
  #expect(controller.discardStatus == .idle && controller.scanWorkflow == nil)
  await expectPreferencesAvailable(controller, true)
}

@MainActor @Test("R18: settings stay unavailable through a manual fallback save and its failure")
func preferencesAvailabilityManualFallback() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let real = SessionStore(directory: directory)
  try await real.saveScanDraft(pendingScan(), lease: real.currentLease())
  let gate = ControllerGate()
  let controller = SessionController(
    storage: ControlledStorage(real, draftGate: gate, failDraft: true), solver: SolverService())
  await controller.load()
  #expect(controller.canSavePreferences)
  #expect(
    controller.switchScanToManual(confirmedCenters: try archivePalette(), confirmed: true)
      == .accepted)
  await gate.waitUntilEntered()
  #expect(controller.manualFallbackStatus == .saving)
  await expectPreferencesAvailable(controller, false)
  await gate.release()
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .failed)
  await expectPreferencesAvailable(controller, false)
  #expect(controller.retryManualFallback() == .accepted)
  await controller.waitForEffects()
  #expect(controller.manualFallbackStatus == .idle && controller.session.phase == .editing)
  await expectPreferencesAvailable(controller, true)
}

@MainActor @Test("R18: settings stay unavailable while local data deletion is pending or failed")
func preferencesAvailabilityDeletion() async throws {
  let directory = try storeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let controller = SessionController(
    storage: ControlledStorage(SessionStore(directory: directory), failDelete: true),
    solver: SolverService())
  await controller.load()
  #expect(controller.send(.deleteLocalData(confirmed: true)) == .accepted)
  #expect(controller.session.phase == .deleting)
  await expectPreferencesAvailable(controller, false)
  await controller.waitForEffects()
  #expect(controller.session.phase == .deletionError)
  await expectPreferencesAvailable(controller, false)
  #expect(controller.send(.retryDeletion) == .accepted)
  await controller.waitForEffects()
  #expect(controller.session.phase == .home)
  await expectPreferencesAvailable(controller, true)
}
