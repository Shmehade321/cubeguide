import CubeCore
import Foundation
import Testing

@testable import CubeSolver3

final class TestClock: SolveClock, @unchecked Sendable {
  private let lock = NSLock()
  private var value: Duration = .zero
  var now: Duration {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  func advance(_ amount: Duration) {
    lock.lock()
    value += amount
    lock.unlock()
  }
}

@Test("V06: runtime verifies real search and honors standard/extended deadlines")
func runtimeDeadlines() throws {
  let cube = try CubeValidation.validate(.solved).get()
  let tables = try searchTables()
  let normal = SolverRuntime.run(cube: cube, tables: tables, budget: .standard)
  guard case .verified(let plan) = normal.outcome else {
    Issue.record("Real solved input must verify")
    return
  }
  #expect(plan.moves.isEmpty)
  for (budget, seconds) in [(SolveBudget.standard, 10), (SolveBudget.extended, 60)] {
    let clock = TestClock()
    let result = SolverRuntime.run(
      cube: cube, tables: tables, budget: budget, clock: clock,
      search: { _, _, _ in
        clock.advance(.seconds(seconds))
        return []
      })
    #expect(result.outcome == .timedOut)
    #expect(result.elapsed == .seconds(seconds))
  }
}

@Test("V06: cancellation before loading never invokes the resource loader")
func cancelBeforeResources() throws {
  let cube = try CubeValidation.validate(.solved).get()
  let token = SolverCancellation()
  token.cancel()
  var loaded = false
  let result = SolverRuntime.run(
    cube: cube, budget: .standard, cancellation: token,
    load: { _ in
      loaded = true
      return try searchTables()
    })
  #expect(result.outcome == .cancelled)
  #expect(!loaded)
}

@Test("V06: resource failure, cancelled load and verification disagreement remain distinct")
func runtimeFailures() throws {
  let cube = try CubeValidation.validate(.solved).get()
  let tables = try searchTables()
  let failed = SolverRuntime.run(
    cube: cube, budget: .standard, load: { _ in throw ResourceError.invalidManifest })
  guard case .resourceFailure = failed.outcome else {
    Issue.record("Missing resources must be a resource failure")
    return
  }
  let cancelled = SolverRuntime.run(
    cube: cube, budget: .standard, load: { _ in throw CancellationError() })
  #expect(cancelled.outcome == .cancelled)
  let wrong = SolverRuntime.run(
    cube: cube, tables: tables, budget: .standard,
    search: { _, _, _ in [Move(face: .up, turns: .clockwise)] })
  #expect(wrong.outcome == .verificationFailure)
  let exhausted = SolverRuntime.run(
    cube: cube, tables: tables, budget: .standard,
    search: { _, _, _ in throw SearchError.exhaustedBounds })
  #expect(exhausted.outcome == .invariantFailure)
}

@Test("V06: cancellation and timeout during each search phase cannot expose instructions")
func runtimePhaseStops() throws {
  let cube = try CubeValidation.validate(
    Facelets.solved.applying(Move.parse("R U2 F' L2 D B2 R' F2 U L' D2 B U' R2 F D' L B' U2 R"))
  ).get()
  let tables = try searchTables()
  for target in [SearchPhase.phaseOne, .phaseTwo, .finished] {
    let clock = TestClock()
    let timed = SolverRuntime.run(
      cube: cube, tables: tables, budget: .standard, clock: clock,
      search: { cube, tables, check in
        try SearchEngine.solve(cube, tables: tables) { phase, nodes in
          if phase == target { clock.advance(.seconds(10)) }
          try check(phase, nodes)
        }
      })
    #expect(timed.outcome == .timedOut)
    let token = SolverCancellation()
    let cancelled = SolverRuntime.run(
      cube: cube, tables: tables, budget: .standard, cancellation: token,
      search: { cube, tables, check in
        try SearchEngine.solve(cube, tables: tables) { phase, nodes in
          if phase == target { token.cancel() }
          try check(phase, nodes)
        }
      })
    #expect(cancelled.outcome == .cancelled)
  }
}

@Test("V06: a deadline reached during loading stops before search and never caches a partial load")
func deadlineDuringLoading() throws {
  let cube = try CubeValidation.validate(.solved).get()
  let clock = TestClock()
  var searched = false
  let result = SolverRuntime.run(
    cube: cube, budget: .standard, clock: clock,
    load: { check in
      clock.advance(.seconds(10))
      try check()
      return try searchTables()
    },
    search: { _, _, _ in
      searched = true
      return []
    })
  #expect(result.outcome == .timedOut)
  #expect(result.tables == nil)
  #expect(!searched)
}
