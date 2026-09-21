#if DEBUG && targetEnvironment(simulator)
import CubeCore
import CubeSession
import CubeSolver3
import Observation
import SwiftUI

// Simulator-only UI fault injection. No scenario selection or solver substitute is
// compiled into Release or physical-device builds. Solver correctness uses the real suite.
enum CalculationTestScenario: String {
  case delayedRealResult, timeout, resourceFailure
  static var requested: Self? {
    ProcessInfo.processInfo.environment["CUBEGUIDE_CALCULATION_UI_TEST"].flatMap(Self.init)
  }
}

struct CalculationTestHost: View {
  let scenario: CalculationTestScenario
  @State private var monitor = CalculationTestMonitor()
  @State private var controller: SessionController?
  @State private var failed = false
  var body: some View {
    VStack(spacing: 0) {
      Text("UI test: injected calculation boundary")
        .accessibilityIdentifier("calculation.testHarness")
      Text(monitor.message).accessibilityIdentifier("calculation.testDelivery")
      if let controller {
        ContentView(controller: controller, isPractice: false)
      } else if failed {
        Text("UI test setup failed").accessibilityIdentifier("calculation.testSetupFailure")
      } else {
        ProgressView("Preparing UI test…")
      }
    }
    .task {
      do {
        let storage = SessionStore()
        try await storage.saveDraft(PracticeExample.draft(), lease: storage.currentLease())
        let opened = SessionController(storage: storage, solver: CalculationTestSolver(scenario, monitor: monitor))
        await opened.load()
        controller = opened
      } catch { failed = true }
    }
  }
}

@MainActor @Observable
private final class CalculationTestMonitor {
  var message = "Waiting for test request"
  func record(_ value: String) { message = value }
}

private actor CalculationTestSolver: SessionSolving {
  let scenario: CalculationTestScenario
  let monitor: CalculationTestMonitor
  init(_ scenario: CalculationTestScenario, monitor: CalculationTestMonitor) {
    self.scenario = scenario
    self.monitor = monitor
  }
  func solve(_ cube: LegalCube, revision: UInt64, budget: SolveBudget) async -> SolverResponse {
    switch scenario {
    case .delayedRealResult:
      // Real search and replay; delay only delivery so XCUITest can press Cancel.
      // Cancellation releases the delay and deliberately returns the stale result.
      let result = await SolverService().solve(cube, revision: revision, budget: budget)
      guard case .verified = result.outcome else {
        await monitor.record("Real solver did not verify the fixture")
        return result
      }
      await monitor.record("Verified result held")
      try? await Task.sleep(for: .seconds(60))
      await monitor.record(Task.isCancelled ? "Cancelled verified result returned" : "Uncancelled result returned")
      return result
    case .timeout:
      return SolverResponse(revision: revision, outcome: .timedOut,
        elapsed: budget == .standard ? .seconds(10) : .seconds(60), visitedNodes: 0)
    case .resourceFailure:
      return SolverResponse(revision: revision, outcome: .resourceFailure("UI fixture"),
        elapsed: .zero, visitedNodes: 0)
    }
  }
}
#endif
