import CubeCore
import Foundation
import Testing

@testable import CubeSolver3

private final class WorkerGate: @unchecked Sendable {
  private let condition = NSCondition()
  private let deliverCompletedResult: Bool
  private var released = false
  private var activeCount = 0
  private var maxCount = 0
  private var calls = 0
  private var ranOnMain = false
  private var firstCancellation: SolverCancellation?
  let entered: AsyncStream<Int>
  private let events: AsyncStream<Int>.Continuation
  init(deliverCompletedResult: Bool = false) {
    self.deliverCompletedResult = deliverCompletedResult
    (entered, events) = AsyncStream.makeStream()
  }
  func run(
    _ cube: LegalCube, _ tables: SolverTables?, _ budget: SolveBudget,
    _ cancellation: SolverCancellation
  ) -> SolverRunResult {
    // Model a result computed before cancellation but delivered after a replacement arrives.
    let completed = deliverCompletedResult
      ? SolverRuntime.run(cube: cube, tables: tables, budget: budget) : nil
    condition.lock()
    calls += 1
    let call = calls
    activeCount += 1
    maxCount = max(maxCount, activeCount)
    ranOnMain = ranOnMain || Thread.isMainThread
    if call == 1 { firstCancellation = cancellation }
    events.yield(call)
    while call == 1 && !released { condition.wait() }
    condition.unlock()
    let result = completed ?? SolverRuntime.run(
      cube: cube, tables: tables, budget: budget, cancellation: cancellation)
    condition.lock()
    activeCount -= 1
    condition.unlock()
    return result
  }
  func release() {
    condition.lock()
    released = true
    condition.broadcast()
    condition.unlock()
  }
  var cancelled: Bool {
    condition.lock()
    defer { condition.unlock() }
    return firstCancellation?.isCancelled ?? false
  }
  var maximumActive: Int {
    condition.lock()
    defer { condition.unlock() }
    return maxCount
  }
  var onMain: Bool {
    condition.lock()
    defer { condition.unlock() }
    return ranOnMain
  }
}

@MainActor
@Test("V06: replacement cancels stale work, keeps one worker and leaves main actor responsive")
func serializedService() async throws {
  let cube = try CubeValidation.validate(.solved).get()
  let gate = WorkerGate()
  defer { gate.release() }
  let service = SolverService(runner: gate.run)
  let first = Task { await service.solve(cube, revision: 1) }
  var events = gate.entered.makeAsyncIterator()
  #expect(await events.next() == 1)
  // Reaching this main-actor continuation while the worker is blocked proves it did not block this actor.
  #expect(!gate.onMain)
  let secondCube = try CubeValidation.validate(
    Facelets.solved.applying([Move(face: .right, turns: .clockwise)])
  ).get()
  let second = Task { await service.solve(secondCube, revision: 2) }
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !gate.cancelled && ContinuousClock.now < deadline { await Task.yield() }
  #expect(gate.cancelled)
  gate.release()
  let a = await first.value
  let b = await second.value
  #expect(a.revision == 1)
  #expect(a.outcome == .cancelled)
  #expect(b.revision == 2)
  guard case .verified(let plan) = b.outcome else {
    Issue.record("Latest real request must verify")
    return
  }
  #expect(plan.original == secondCube.facelets)
  #expect(gate.maximumActive == 1)
}

@Test("V06: explicit service cancellation cannot return a completed stale plan")
func explicitServiceCancellation() async throws {
  let cube = try CubeValidation.validate(.solved).get()
  let gate = WorkerGate(deliverCompletedResult: true)
  defer { gate.release() }
  let service = SolverService(runner: gate.run)
  let request = Task { await service.solve(cube, revision: 7) }
  var events = gate.entered.makeAsyncIterator()
  #expect(await events.next() == 1)
  await service.cancel()
  #expect(gate.cancelled)
  gate.release()
  let result = await request.value
  #expect(result.revision == 7)
  #expect(result.outcome == .cancelled)
}

@Test("V06: caller task cancellation reaches the detached worker")
func parentTaskCancellation() async throws {
  let cube = try CubeValidation.validate(.solved).get()
  let gate = WorkerGate()
  defer { gate.release() }
  let service = SolverService(runner: gate.run)
  let request = Task { await service.solve(cube, revision: 8) }
  var events = gate.entered.makeAsyncIterator()
  #expect(await events.next() == 1)
  request.cancel()
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !gate.cancelled && ContinuousClock.now < deadline { await Task.yield() }
  #expect(gate.cancelled)
  gate.release()
  #expect(await request.value.outcome == .cancelled)
}

private final class CacheObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var observations: [Bool] = []
  func run(
    _ cube: LegalCube, _ tables: SolverTables?, _ budget: SolveBudget,
    _ cancellation: SolverCancellation
  ) -> SolverRunResult {
    lock.lock()
    observations.append(tables != nil)
    lock.unlock()
    return SolverRuntime.run(cube: cube, tables: tables, budget: budget, cancellation: cancellation)
  }
  var loaded: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return observations
  }
}

@Test("V06: completed requests reuse verified tables and cancelled callers do not launch work")
func serviceCachesValidatedResources() async throws {
  let cube = try CubeValidation.validate(.solved).get()
  let observation = CacheObservation()
  let service = SolverService(runner: observation.run)
  for revision in UInt64(1)...2 {
    let response = await service.solve(cube, revision: revision)
    guard case .verified = response.outcome else {
      Issue.record("Real solved request must verify")
      return
    }
  }
  let cancelled = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    return await service.solve(cube, revision: 3)
  }
  #expect(await cancelled.value.outcome == .cancelled)
  #expect(observation.loaded == [false, true])
}
