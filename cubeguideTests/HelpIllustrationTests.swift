import CubeCore
import Testing

@testable import cubeguide

@MainActor
@Test("R08/R15: Help has one orientation diagram for every face using the core top-neighbor model")
func helpOrientationPairsUseCubeCore() {
  #expect(HelpDiagramModel.orientationPairs.count == 6)
  #expect(HelpDiagramModel.orientationPairs.map(\.face) == Face.allCases)
  for pair in HelpDiagramModel.orientationPairs {
    #expect(pair.top == pair.face.topNeighbor)
    #expect(pair.face != pair.top)
    #expect(pair.face != pair.top.opposite)
  }
}
