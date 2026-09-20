import CubeCore
import Foundation

public enum SolveBudget: Sendable { case standard, extended }
public enum SolveOutcome: Equatable, Sendable {
  case verified(VerifiedPlan)
  case cancelled, timedOut
  case invalidInput(ValidationIssues)
  case resourceFailure(String)
  case verificationFailure, invariantFailure
}
package protocol SolveClock: Sendable { var now: Duration { get } }
package struct MonotonicSolveClock: SolveClock {
  private let origin = ContinuousClock.now
  package var now: Duration { origin.duration(to: .now) }
}
package final class SolverCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  package func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
  package var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}
package struct SolverRunResult: Sendable {
  package let outcome: SolveOutcome, tables: SolverTables?, elapsed: Duration, visitedNodes: Int
}
private enum SolverStop: Error { case cancelled, timedOut }

package enum SolverRuntime {
  package static func run(
    cube: LegalCube, tables: SolverTables? = nil, budget: SolveBudget,
    clock: any SolveClock = MonotonicSolveClock(),
    cancellation: SolverCancellation = SolverCancellation(),
    load: ((() throws -> Void) throws -> SolverTables) = {
      try SolverResources.loadBundled(checkCancellation: $0)
    },
    search: (
      (LegalCube, SolverTables, @escaping (SearchPhase, Int) throws -> Void) throws -> [Move]
    ) = { try SearchEngine.solve($0, tables: $1, check: $2) }
  ) -> SolverRunResult {
    let started = clock.now
    let limit: Duration = budget == .standard ? .seconds(10) : .seconds(60)
    var loaded = tables
    var visited = 0
    func finish(_ outcome: SolveOutcome) -> SolverRunResult {
      SolverRunResult(
        outcome: outcome, tables: loaded, elapsed: clock.now - started, visitedNodes: visited)
    }
    func checkpoint() throws {
      if cancellation.isCancelled { throw SolverStop.cancelled }
      if clock.now - started >= limit { throw SolverStop.timedOut }
    }
    do {
      try checkpoint()
      if loaded == nil {
        do { loaded = try load(checkpoint) } catch let stop as SolverStop {
          throw stop
        } catch is CancellationError { throw SolverStop.cancelled } catch {
          return finish(.resourceFailure("Bundled solver resources are missing or corrupt."))
        }
      }
      guard let verifiedTables = loaded else { return finish(.invariantFailure) }
      try checkpoint()
      let moves = try search(cube, verifiedTables) { _, nodes in
        visited = nodes
        try checkpoint()
      }
      try checkpoint()
      let verification = Replay.verify(moves, for: cube, resourceVersion: verifiedTables.version)
      try checkpoint()
      switch verification {
      case .success(let plan): return finish(.verified(plan))
      case .failure: return finish(.verificationFailure)
      }
    } catch SolverStop.cancelled { return finish(.cancelled) } catch SolverStop.timedOut {
      return finish(.timedOut)
    } catch is CancellationError { return finish(.cancelled) } catch {
      return finish(.invariantFailure)
    }
  }
}
