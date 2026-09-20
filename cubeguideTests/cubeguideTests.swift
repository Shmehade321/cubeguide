import CubeCore
import CubeSolver3
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
