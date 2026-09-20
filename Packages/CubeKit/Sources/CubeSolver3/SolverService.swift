import CubeCore
import Foundation

public struct SolverResponse: Sendable {
  public let revision: UInt64, outcome: SolveOutcome, elapsed: Duration, visitedNodes: Int
  public init(revision: UInt64, outcome: SolveOutcome, elapsed: Duration, visitedNodes: Int) {
    self.revision = revision
    self.outcome = outcome
    self.elapsed = elapsed
    self.visitedNodes = visitedNodes
  }
}
package typealias SolverRunner =
  @Sendable (LegalCube, SolverTables?, SolveBudget, SolverCancellation) -> SolverRunResult
public actor SolverService {
  private let runner: SolverRunner
  private var cachedTables: SolverTables?
  private var latestRequest = UUID()
  private struct Active {
    let id: UUID
    let task: Task<SolverRunResult, Never>
    let cancellation: SolverCancellation
  }
  private var active: Active?

  public init() {
    runner = { SolverRuntime.run(cube: $0, tables: $1, budget: $2, cancellation: $3) }
  }
  package init(runner: @escaping SolverRunner) { self.runner = runner }

  public func solve(_ cube: LegalCube, revision: UInt64, budget: SolveBudget = .standard) async
    -> SolverResponse
  {
    let started = ContinuousClock.now
    func response(_ outcome: SolveOutcome, nodes: Int = 0) -> SolverResponse {
      SolverResponse(
        revision: revision, outcome: outcome, elapsed: started.duration(to: .now),
        visitedNodes: nodes)
    }
    guard !Task.isCancelled else { return response(.cancelled) }
    let id = UUID()
    latestRequest = id
    if let previous = active {
      previous.cancellation.cancel()
      previous.task.cancel()
      let settled = await previous.task.value
      if cachedTables == nil { cachedTables = settled.tables }
    }
    // Another request can arrive while the previous worker is settling.
    guard latestRequest == id, !Task.isCancelled else { return response(.cancelled) }
    let cancellation = SolverCancellation()
    let tables = cachedTables
    let runner = self.runner
    let task = Task.detached(priority: .userInitiated) {
      runner(cube, tables, budget, cancellation)
    }
    active = Active(id: id, task: task, cancellation: cancellation)
    let result = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      cancellation.cancel()
      task.cancel()
    }
    if active?.id == id { active = nil }
    if cachedTables == nil { cachedTables = result.tables }
    guard latestRequest == id, !Task.isCancelled, !cancellation.isCancelled else {
      return response(.cancelled, nodes: result.visitedNodes)
    }
    return response(result.outcome, nodes: result.visitedNodes)
  }

  public func cancel() {
    latestRequest = UUID()
    active?.cancellation.cancel()
    active?.task.cancel()
  }
}
