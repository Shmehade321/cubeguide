import Testing
import CubeCore
@testable import cubeguide

struct AppCompositionTests {
    @MainActor
    @Test("R20: app links CubeCore and exposes all canonical faces")
    func packageIntegration() {
        #expect(AppDependencies().canonicalFaces.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
    }
}
