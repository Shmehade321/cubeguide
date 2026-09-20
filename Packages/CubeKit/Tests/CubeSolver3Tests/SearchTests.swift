import CubeCore
import Testing

@testable import CubeSolver3

private let sharedSearchTables = Result { try SolverResources.loadBundled() }
func searchTables() throws -> SolverTables { try sharedSearchTables.get() }

@Test("V05: phase goals work at depth zero and just-below/at-depth bounds")
func searchDepthBoundaries() throws {
  let tables = try searchTables()
  #expect(try SearchEngine.phaseOne(.solved, tables: tables, maximumDepth: 0).isEmpty)
  #expect(try SearchEngine.phaseTwo(.solved, tables: tables, maximumDepth: 0).isEmpty)
  let r = Cubies.solved.applying(Move(face: .right, turns: .clockwise))
  #expect(throws: SearchError.self) {
    try SearchEngine.phaseOne(r, tables: tables, maximumDepth: 0)
  }
  let first = try SearchEngine.phaseOne(r, tables: tables, maximumDepth: 1)
  #expect(first.count == 1)
  var endpoint = r
  for move in first { endpoint = endpoint.applying(move) }
  _ = try endpoint.phaseTwoCoordinates()
  let u = Cubies.solved.applying(Move(face: .up, turns: .clockwise))
  #expect(throws: SearchError.self) {
    try SearchEngine.phaseTwo(u, tables: tables, maximumDepth: 0)
  }
  let second = try SearchEngine.phaseTwo(u, tables: tables, maximumDepth: 1)
  #expect(second == [Move(face: .up, turns: .counterclockwise)])
}

@Test("V05: solve all 18 single turns with original tables and independent replay")
func singleTurnSearch() throws {
  let tables = try searchTables()
  for face in Face.allCases {
    for turns in QuarterTurns.allCases {
      let state = Facelets.solved.applying([Move(face: face, turns: turns)])
      let cube = try CubeValidation.validate(state).get()
      let solution = try SearchEngine.solve(cube, tables: tables)
      #expect(!solution.isEmpty)
      #expect(solution.count <= 30)
      #expect(
        try Replay.verify(solution, for: cube, resourceVersion: tables.version).get().original
          == state)
    }
  }
}

@Test("V05: phase-two starts with fresh move history after a phase-one R endpoint")
func phaseBoundaryHistory() throws {
  let tables = try searchTables()
  let cube = try CubeValidation.validate(
    Facelets.solved.applying([Move(face: .right, turns: .clockwise)])
  ).get()
  let solution = try SearchEngine.solve(
    cube, tables: tables, bounds: SearchBounds(phaseOne: 1, phaseTwo: 1))
  // Stable phase-one traversal first reaches subgroup through R; phase two must permit R2.
  #expect(solution == [Move(face: .right, turns: .clockwise), Move(face: .right, turns: .half)])
  #expect(cube.facelets.applying(solution) == .solved)
}

private enum TestStop: Error { case stop }
@Test("V06: search propagates cancellation/checkpoint errors at entry and phase boundaries")
func searchCheckpoints() throws {
  let tables = try searchTables()
  let cube = try CubeValidation.validate(.solved).get()
  for target in [SearchPhase.starting, .phaseOne, .phaseTwo, .finished] {
    var reached = false
    #expect(throws: TestStop.self) {
      try SearchEngine.solve(cube, tables: tables) { phase, _ in
        if phase == target {
          reached = true
          throw TestStop.stop
        }
      }
    }
    #expect(reached)
  }
}

@Test("V06: reject invalid search limits and phase-two states outside its subgroup")
func invalidSearchInputs() throws {
  let tables = try searchTables()
  for depth in [-1, 13, Int.max] {
    #expect(throws: SearchError.self) {
      try SearchEngine.phaseOne(.solved, tables: tables, maximumDepth: depth)
    }
  }
  for depth in [-1, 19, Int.max] {
    #expect(throws: SearchError.self) {
      try SearchEngine.phaseTwo(.solved, tables: tables, maximumDepth: depth)
    }
  }
  let r = Cubies.solved.applying(Move(face: .right, turns: .clockwise))
  #expect(throws: CoordinateError.self) {
    try SearchEngine.phaseTwo(r, tables: tables, maximumDepth: 18)
  }
}

private let checkpointScramble = "R U2 F' L2 D B2 R' F2 U L' D2 B U' R2 F D' L B' U2 R"

@Test("V05: multi-phase scramble solves and reports bounded checkpoint spacing")
func multiPhaseSearch() throws {
  let tables = try searchTables()
  let cube = try CubeValidation.validate(Facelets.solved.applying(Move.parse(checkpointScramble)))
    .get()
  var previous = 0
  var phaseOneNodes = 0
  var phaseTwoNodes = 0
  let deadline = ContinuousClock.now.advanced(by: .seconds(10))
  let solution = try SearchEngine.solve(cube, tables: tables) { phase, nodes in
    #expect(nodes - previous <= 1024)
    previous = nodes
    if phase == .phaseOne { phaseOneNodes = nodes }
    if phase == .phaseTwo { phaseTwoNodes = nodes }
    if ContinuousClock.now >= deadline { throw TestStop.stop }
  }
  #expect(cube.facelets.applying(solution) == .solved)
  #expect(solution.count <= 30)
  print(
    "Checkpoint fixture: phase-one nodes \(phaseOneNodes), phase-two cumulative nodes \(phaseTwoNodes), solution length \(solution.count)"
  )
}

@Test("V06: cancellation stops an active search in both phases")
func midPhaseCancellation() throws {
  let tables = try searchTables()
  let cube = try CubeValidation.validate(Facelets.solved.applying(Move.parse(checkpointScramble)))
    .get()
  for target in [SearchPhase.phaseOne, .phaseTwo] {
    var entry: Int? = nil
    var stopped = false
    #expect(throws: TestStop.self) {
      try SearchEngine.solve(cube, tables: tables) { phase, nodes in
        if phase == target {
          if entry == nil {
            entry = nodes
          } else if nodes > entry! {
            stopped = true
            throw TestStop.stop
          }
        }
      }
    }
    #expect(stopped)
  }
}

@Test("V05: exhaust a shallow heuristic bound before succeeding at the next iterative depth")
func exhaustedHeuristicBounds() throws {
  let tables = try searchTables()
  // Breadth-first enumeration located these gaps in the paired abstractions.
  // Phase-one coordinates (540,0,421) have h=3 but subgroup distance 4.
  let firstState = try Move.parse("R U R U2").reduce(Cubies.solved) { $0.applying($1) }
  #expect(max(tables[.twistSliceDistance][540 * 495 + 421], tables[.flipSliceDistance][421]) == 3)
  #expect(throws: SearchError.self) {
    try SearchEngine.phaseOne(firstState, tables: tables, maximumDepth: 3)
  }
  let first = try SearchEngine.phaseOne(firstState, tables: tables, maximumDepth: 4)
  #expect(first.count == 4)
  _ = try first.reduce(firstState) { $0.applying($1) }.phaseTwoCoordinates()
  // Phase-two coordinates (37957,288,19) have h=4 but exact distance 5.
  let secondState = try Move.parse("R2 F2 U2 R2 F2").reduce(Cubies.solved) { $0.applying($1) }
  #expect(max(tables[.cornerSlicePermDistance][37957 * 24 + 19], tables[.edgeSlicePermDistance][288 * 24 + 19]) == 4)
  #expect(throws: SearchError.self) {
    try SearchEngine.phaseTwo(secondState, tables: tables, maximumDepth: 4)
  }
  let second = try SearchEngine.phaseTwo(secondState, tables: tables, maximumDepth: 5)
  #expect(second.count == 5)
  #expect(try second.reduce(secondState) { $0.applying($1) }.facelets() == .solved)
}
