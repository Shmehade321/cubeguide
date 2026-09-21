import CubeCore
import CubeSession
import CubeSolver3
import Foundation
import Testing

@testable import cubeguide

struct AppCompositionTests {
  @MainActor
  @Test("R20: app links CubeCore and exposes all canonical faces")
  func packageIntegration() {
    #expect(AppDependencies().canonicalFaces.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
  }

  @MainActor
  @Test("R06: installed app loads bundled tables and independently verifies a literal scramble")
  func bundledSolverIntegration() async throws {
    let faces = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
    let cube = try CubeValidation.validate(faces).get()
    let response = await AppDependencies().solver.solve(cube, revision: 42)
    #expect(response.revision == 42)
    guard case .verified(let plan) = response.outcome else {
      Issue.record("App must produce a verified plan using its bundled solver resources")
      return
    }
    #expect(plan.original == faces)
    #expect(!plan.moves.isEmpty)
    #expect(faces.applying(plan.moves) == .solved)
  }
}

@MainActor
@Test(
  "R18: app guide store saves offline and restores; protection attributes checked on physical devices"
)
func protectedGuideStorage() async throws {
  let directory = AppDependencies.guideDirectory.appendingPathComponent("test-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  #expect(directory.path.hasPrefix(URL.applicationSupportDirectory.path + "/"))
  let dependencies = AppDependencies(guideDirectory: directory)
  let faces = try Facelets(notation: "UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB")
  var session = Session()
  session = SessionReducer.reduce(session, event: .startManual(replacing: false)).session
  session = SessionReducer.reduce(session, event: .validate(faces)).session
  session = SessionReducer.reduce(session, event: .consent(true)).session
  let cube = try #require(session.confirmedCube)
  let result = await dependencies.solver.solve(cube, revision: session.revision)
  session = SessionReducer.reduce(session, event: .solveResult(result)).session
  let request = try #require(session.pendingSave)
  let palette = try CenterPalette([.green, .white, .orange, .blue, .yellow, .red])
  let store = dependencies.guideStore
  try await store.save(request, palette: palette, lease: store.currentLease())
  // Simulator does not expose the protection attribute on this runtime.
  // Physical qualification must run these assertions and locked-device I/O checks.
  #if !targetEnvironment(simulator)
    let path = directory.appendingPathComponent("guide.json").path
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect(attributes[.protectionKey] as? String == FileProtectionType.complete.rawValue)
    let folderAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect(folderAttributes[.protectionKey] as? String == FileProtectionType.complete.rawValue)
  #endif
  #expect(
    try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  let restored = try #require(try await store.load())
  #expect(restored.progress == request.progress)
  #expect(restored.palette == palette)
  let resumed = try Session(restoring: restored)
  #expect(resumed.phase == .resumeCheck && !resumed.aligned)
  _ = try await store.delete(lease: store.currentLease())
  #expect(try await store.load() == nil)
}
